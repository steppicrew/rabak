#!/usr/bin/perl

package Rabak::Backup;

# this class connects a target with a source

use warnings;
use strict;
#use vars qw(@ISA);

use Data::Dumper;
use Rabak::Log;
use POSIX qw(strftime);

sub new {
    my $class= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;
    
    my $self= {
        SOURCE => $oSourcePeer,
        TARGET => $oTargetPeer,
        BACKUP_DATA => undef,
    };
    bless $self, $class;
}

sub METAVERSION {1};

sub run {
    my $self= shift;
    my $hBaksetData= shift || {};
    
    # copy bakset data
    for my $sKey (keys %$hBaksetData) {
        $self->{BACKUP_DATA}{$sKey}= $hBaksetData->{$sKey};
    }
    
    my $iResult= $self->_setup();
    $iResult= $self->_run() unless $iResult;
    $self->_cleanup($iResult);
    return $iResult
}

sub _setup {
    my $self= shift;

    my $oSourcePeer= $self->{SOURCE};
    my $oTargetPeer= $self->{TARGET};
    
    logger->info("Backup start at " . strftime("%F %X", localtime) . ": "
        . ($oSourcePeer->getName() || $oSourcePeer->getFullPath()) . ", "
#        . $self->get_value("title")
    );
    logger->incIndent();

    # prepare target for backup
    my $asSourceExts= Rabak::Set->GetAllPathExtensions($oSourcePeer);
    # TODO: may be we only need "%d" as $sBakDay?
    my $sBakDay= strftime("%Y-%m-%d", @{$self->{BACKUP_DATA}{BAKSET_TIME}});

    my $hDirs= $self->{BACKUP_DATA}{ALL_BAKSET_DIRS};

    my @sBakBaseDirs= $oTargetPeer->getBakdirsByExts(
        $self->{BACKUP_DATA}{ALL_BAKSET_EXTS},
        $asSourceExts,
        $hDirs,
    );

    my $sSubSet= '';
    my $aLastBakBaseDir= $sBakBaseDirs[0];
    if (scalar @sBakBaseDirs && $hDirs->{$aLastBakBaseDir}{date} eq $sBakDay) {
        $sSubSet= $hDirs->{$aLastBakBaseDir}{subset};

        # TODO: do we have to die here?
        die "Maximum of 1000 backups reached!" if $sSubSet eq '_999';
        if (!$sSubSet) {
            $sSubSet= '_001';
        }
        else {
            $sSubSet=~ s/^_0*//;
            $sSubSet= sprintf("_%03d", $sSubSet + 1);
        }
    }

    my $sSourceExt= $asSourceExts->[0];
    my $sSourceSet= $sBakDay . $sSubSet;
    my $sSourceSubdir= $sSourceSet . $sSourceExt;
    my $sBakDir= $self->{BACKUP_DATA}{BAKSET_DIR} . '/' . $sSourceSubdir;
    
    $self->_convertBackupDirs(\@sBakBaseDirs);

    $self->{BACKUP_DATA}{OLD_BACKUP_DIRS}= \@sBakBaseDirs;
    $self->{BACKUP_DATA}{SOURCE_EXT}= $sSourceExt;
    $self->{BACKUP_DATA}{BACKUP_SUBSET}= $sSubSet;
    $self->{BACKUP_DATA}{BACKUP_SUBDIR}= $sSourceSubdir;
    $self->{BACKUP_DATA}{BACKUP_DIR}= $sBakDir;
    $self->{BACKUP_DATA}{BACKUP_DATA_DIR}= $sBakDir . '/data';
    $self->{BACKUP_DATA}{BACKUP_META_DIR}= $sBakDir . '/meta';
    
    logger->info("Backup \"$sBakDay$sSourceExt\" exists, using subset \"$sSourceSubdir\".") if $sSubSet;

    $oTargetPeer->mkdir($self->{BACKUP_DATA}{BACKUP_DIR});
    $oTargetPeer->mkdir($self->{BACKUP_DATA}{BACKUP_DATA_DIR});
    $oTargetPeer->mkdir($self->{BACKUP_DATA}{BACKUP_META_DIR});
    $self->_writeVersion($sBakDir);
    
    if ($oSourcePeer->get_value('inode_inventory') && !$oTargetPeer->pretend() && !$oTargetPeer->is_remote()) {
        my $inodeStore= Rabak::InodeCache->new({
            db_inodes_dir => $oTargetPeer->getPath($self->{BACKUP_DATA}{BAKSET_META_DIR}),
        });
        logger->info("Preparing information store for inode inventory...");
        $inodeStore->prepareInformationStore(
            $oTargetPeer->getPath($self->{BACKUP_DATA}{BACKUP_DATA_DIR}),
            $oTargetPeer->getPath($self->{BACKUP_DATA}{BACKUP_META_DIR} . '/files_inode.db'),
        );
        logger->info("...done");
        
        $self->{BACKUP_DATA}{INODE_STORE}= $inodeStore;
        my @sInventFiles= ();
        $self->{BACKUP_DATA}{FILE_CALLBACK}= sub{
            # add only existant files, remember nonexistant (files may be created after logging)
            push @sInventFiles, @_;
            my $count= scalar @sInventFiles;
            while ($count--) {
                my $sFile= shift @sInventFiles;
                if (-e $sFile) {
                    $inodeStore->addFile($sFile);
                    next;
                }
                push @sInventFiles, $sFile;
            }
            return scalar @sInventFiles;
        };
    }

    return $oSourcePeer->prepareBackup();
}

sub _run {
    my $self= shift;

    my @sOldDataDirs= grep {-d} map { $_ . '/data' } @{$self->{BACKUP_DATA}{OLD_BACKUP_DIRS}};

    return $self->{SOURCE}->run(
        $self->{TARGET},
        {
            DATA_DIR => $self->{TARGET}->getPath($self->{BACKUP_DATA}{BACKUP_DATA_DIR}),
            META_DIR => $self->{TARGET}->getPath($self->{BACKUP_DATA}{BACKUP_META_DIR}),
            OLD_DATA_DIRS => \@sOldDataDirs,
            FILE_CALLBACK => $self->{BACKUP_DATA}{FILE_CALLBACK},
        },
    );
}

sub _cleanup {
    my $self= shift;
    my $iResult= shift;

    my $oSourcePeer= $self->{SOURCE};
    my $oTargetPeer= $self->{TARGET};
    
    my $sSourceSet= $self->{BACKUP_DATA}{BACKUP_SUBDIR};

    $oSourcePeer->finishBackup($iResult);

    if ($self->{BACKUP_DATA}{INODE_STORE}) {
        logger->info("Finishing information store for inode inventory...");
        # finish up previously nonexistant files
        $self->{BACKUP_DATA}{FILE_CALLBACK}->() if $self->{BACKUP_DATA}{FILE_CALLBACK};
        $self->{BACKUP_DATA}{INODE_STORE}->finishInformationStore();
        logger->info("..done");
    }

    if ($iResult) {
        logger->error("Backup failed: " . $oSourcePeer->get_last_error());
        $iResult= 9;
    }
    else {
        logger->info("Done!");
    }

    unless ($oTargetPeer->pretend()) {
        unless ($iResult) {
            # TODO: reimplement inodeinventory and dupmerge
#            $oTargetPeer->inodeInventory();
#            $oTargetPeer->dupMerge();
            # remove old dirs if backup was successfully done
            $oTargetPeer->remove_old($oSourcePeer->get_value('keep'), $self->{BACKUP_DATA}{OLD_BACKUP_DIRS});
        }

        my $sSourceExt= $self->{BACKUP_DATA}{SOURCE_EXT};
        $sSourceExt=~ s/^\./\-/;
        my $sCurrentLink= "current" . $self->{BACKUP_DATA}{BAKSET_EXT} . $sSourceExt;
        $oTargetPeer->unlink($sCurrentLink);
        $oTargetPeer->symlink($self->{BACKUP_DATA}{BACKUP_DIR}, $sCurrentLink);
    }

    logger->decIndent();
    logger->info("Backup done at "
        . strftime("%F %X", localtime) . ": "
        . ($oSourcePeer->getName() || $oSourcePeer->getFullPath()) . ", "
        . $sSourceSet
    );
}

sub _convertBackupDirs {
    my $self= shift;
    my $aDirs= shift;
    
    my $oTargetPeer= $self->{TARGET};
    
    my $hConvFuncs= {
        0 => sub {
            # convert (unversioned) backup directory to meta version 1
            my $sDir= shift;
            my $sTmpDir= $sDir . '.tmp.' . $$;
            $oTargetPeer->mkdir($sTmpDir);
            $oTargetPeer->rename($sDir, $sTmpDir . '/data');
            $oTargetPeer->rename($sTmpDir, $sDir);
            $oTargetPeer->mkdir($sDir . '/meta');
            return 1;
        },
    };
    
    for my $sDir (@$aDirs) {
        my $sMetaVersion= $self->_getMetaVersion($sDir);
        while ($sMetaVersion != $self->METAVERSION()) {
            die "Internal error: Meta version \"$sMetaVersion\" has no convert function!" unless $hConvFuncs->{$sMetaVersion};
            my $sOldMetaVersion= $sMetaVersion;
            $sMetaVersion= $hConvFuncs->{$sMetaVersion}->($sDir);
            $self->_writeVersion($sDir, $sMetaVersion);
            logger->info("Converted backup directory from version \"$sOldMetaVersion\" to \"$sMetaVersion\".");
        }
    }
}

sub _getMetaVersionFile {
    my $self= shift;
    my $sDir= shift || '';
    return $sDir . '/meta/.version';
}

sub _getMetaVersion {
    my $self= shift;
    my $sDir= shift;
    
    my $oTargetPeer= $self->{TARGET};
    my $sMetaVersionFile= $self->_getMetaVersionFile($sDir);   

    return 0 unless $oTargetPeer->isFile($sMetaVersionFile);
    my $sVersion= $oTargetPeer->cat($sMetaVersionFile);
    return -1 unless defined $sVersion;
    chomp $sVersion;
    return $sVersion;
}

sub _writeVersion {
    my $self= shift;
    my $sDir= shift;
    my $sVersion= shift || $self->METAVERSION();
    
    my $sMetaVersionFile= $self->_getMetaVersionFile($sDir);   

    $self->{TARGET}->unlink($sMetaVersionFile);
    $self->{TARGET}->echo($sMetaVersionFile, $sVersion);
}

1;
