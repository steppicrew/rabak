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

my %METAFILENAMES=(
    version    => 'Version',
    error      => 'Error',
    result     => 'Result',
    statistics => 'Statistics',
);

sub run {
    my $self= shift;
    my $hBaksetData= shift;
    
    $self->_run() unless $self->_setup($hBaksetData);
    return $self->_cleanup();
}

sub _setup {
    my $self= shift;
    my $hBaksetData= shift;

    my $oSourcePeer= $self->{SOURCE};
    my $oTargetPeer= $self->{TARGET};
    
    my $sSourceName= $oSourcePeer->getName() || $oSourcePeer->getFullPath();
    logger->info('Backup start at ' . strftime('%F %X', localtime) . ': ' . $sSourceName);
    logger->incIndent();

    # prepare target for backup
    my $asSourceExts= Rabak::Set->GetAllPathExtensions($oSourcePeer);
    # TODO: may be we only need "%d" as $sBakDay?
    my $sBakDay= strftime("%Y-%m-%d", @{$hBaksetData->{BAKSET_TIME}});

    my $hDirs= $hBaksetData->{ALL_BAKSET_DIRS};

    my @sBakBaseDirs= $oTargetPeer->getBakdirsByExts(
        $hBaksetData->{ALL_BAKSET_EXTS},
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
    my $sBakDir= $hBaksetData->{BAKSET_DIR} . '/' . $sSourceSubdir;
    my $sBakDataDir= $sBakDir . '/data';
    my $sBakMetaDir= $sBakDir . '/meta';
    
    $self->_convertBackupDirs(\@sBakBaseDirs);

    $self->{BACKUP_DATA}{OLD_BACKUP_DATA_DIRS}= [map { $_ . '/data' } @sBakBaseDirs];
    $self->{BACKUP_DATA}{BACKUP_DATA_DIR}= $sBakDataDir;
    $self->{BACKUP_DATA}{BACKUP_META_DIR}= $sBakMetaDir;
    
    logger->info("Backup \"$sBakDay$sSourceExt\" exists, using subset \"$sSourceSubdir\".") if $sSubSet;

    $oTargetPeer->mkdir($sBakDir);
    $oTargetPeer->mkdir($sBakDataDir);
    $oTargetPeer->mkdir($sBakMetaDir);
    $self->_writeVersion($sBakDir);
    
    ########################################################
    # set cleanup chain
    ########################################################
    
    # start finish functions with cleaning up source
    my @fFinish= (
        sub {$oSourcePeer->finishBackup($self->{BACKUP_DATA}{BACKUP_RESULT})},
    );
    
    unless ($oTargetPeer->pretend()) {
        # add finish function for inode inventory (and create per-file-callback function)
        if ($oSourcePeer->getValue('inode_inventory')) {
            my $sInodesDb= $oTargetPeer->getPath($hBaksetData->{BAKSET_META_DIR} . '/inodes.db');
            my $sFilesInodeDb= $oTargetPeer->getPath($sBakMetaDir . '/files_inode.db');
            if ($oTargetPeer->isRemote()) {
                # special handling for remote targets (see idea below)
                my ($fh, $sFileListFile)= $oTargetPeer->localTempfile(SUFFIX => '.filelist.txt');

                $self->{BACKUP_DATA}{FILE_CALLBACK}= sub {
                    print $fh join "\n", @_, '';
                };

                # remember temporary->remote file names for later uploading
                my $hTempFilesMap= {};
                my $inodeStore;
                push @fFinish, sub {
                    close $fh;
                    logger->verbose("Preparing information store for inode inventory...");
                    logger->incIndent();
                    logger->debug("Downloading \"inodes.db\"...");
                    my $sLocalInodesDb= $oTargetPeer->getLocalFile($sInodesDb, SUFFIX => '.inodes.db');
                    $hTempFilesMap->{$sInodesDb}= $sLocalInodesDb;
                    logger->debug("done");
                    $inodeStore= Rabak::InodeCache->new({
                        inodes_db => $sLocalInodesDb,
                    });
                    my $sLocalFilesInodeDb= $oTargetPeer->localTempfile(SUFFIX => '.files_inode.db');
                    $hTempFilesMap->{$sFilesInodeDb}= $sLocalFilesInodeDb;
                    $inodeStore->prepareInformationStore(
                        $oTargetPeer->getPath($sBakDataDir),
                        $sLocalFilesInodeDb,
                    );
                    logger->decIndent();
                    logger->verbose("done");
                    
                    # idea: cat file list to remote site, return lstat's result (+ file name)
                    # and insert output into inode store
                    open $fh, $sFileListFile or die "Could not open file \"$sFileListFile\" for reading.";
                    my %Handles= (
                        STDIN => sub {
                            return scalar <$fh>;
                        },
                        STDOUT => sub {
                            for my $sLine (@_) {
                                chomp $sLine;
                                my @sParams= split /\:/, $sLine, 14;        #/
                                if (scalar @sParams < 14) {
                                    logger->error("Error parsing inventory data (\"$sLine\").");
                                    next;
                                }
                                # rotate file name from end to front
                                unshift @sParams, pop(@sParams);
                                $inodeStore->addFile(@sParams);
                            }
                        },
                        STDERR => sub {
                            logger->error(@_);
                        },
                    );
                    $oTargetPeer->runPerl(
                        '# get data for indoe inventory
                        while (<>) {
                            chomp;
                            print join(":", lstat, $_), "\n";
                        }',
                        undef, undef, \%Handles,
                    );
                    close $fh;
                };
                
                if ($oSourcePeer->getValue('merge_duplicates')) {
                    push @fFinish, $self->_buildDupMerge(
                        $oTargetPeer, \$inodeStore, \@sBakBaseDirs, $hTempFilesMap,
                    );
                }

                push @fFinish, sub {
                    logger->verbose("Finishing information store...");
                    logger->incIndent();
                    $inodeStore->finishInformationStore();
                    logger->verbose("Uploading temporary files to target...");
                    logger->incIndent();
                    for my $sRemoteFile (sort keys %$hTempFilesMap) {
                        logger->debug("Uploading \"$sRemoteFile\".");
                        $oTargetPeer->copyLocalFileToRemote($hTempFilesMap->{$sRemoteFile}, $sRemoteFile, SAVE_COPY => 1,);
                    }
                    logger->decIndent();
                    logger->verbose("done");
                    logger->decIndent();
                    logger->verbose("done");
                };
            }
            else {
                # handle inode inventory for local targets
                my $inodeStore= Rabak::InodeCache->new({
                    inodes_db => $sInodesDb,
                });
                logger->verbose("Preparing information store for inode inventory...");
                $inodeStore->prepareInformationStore(
                    $oTargetPeer->getPath($sBakDataDir),
                    $sFilesInodeDb,
                );
                logger->verbose("done");
                
                my @sInventFiles= ();
 
                $self->{BACKUP_DATA}{FILE_CALLBACK}= sub {
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
                
                push @fFinish, sub {
                    # finish up previously nonexistant files
                    $self->{BACKUP_DATA}{FILE_CALLBACK}->();
                };

                if ($oSourcePeer->getValue('merge_duplicates')) {
                    push @fFinish, $self->_buildDupMerge(
                        $oTargetPeer, \$inodeStore, \@sBakBaseDirs
                    );
                }
    
                push @fFinish, sub {
                    logger->verbose("Finishing information store...");
                    $inodeStore->finishInformationStore();
                    logger->verbose("done");
                };
            }
        }
        elsif ($oSourcePeer->getValue('merge_duplicates')) {
            logger->error("Option \"merge_duplicates\" is only allowed if option \"inode_inventory\" si given too! Ignoring.")
        }
    }
    
    # add finish function to log backup result
    push @fFinish, sub {
        if ($self->{BACKUP_DATA}{BACKUP_RESULT}) {
            logger->error("Backup failed: " . $oSourcePeer->getLastError());
            $self->{BACKUP_DATA}{BACKUP_RESULT}= 9;
        }
        else {
            logger->info("Done!");
        }
    };

    unless ($oTargetPeer->pretend()) {
        # add finish function to remove old backups and symlink current directory
        push @fFinish, sub {
            unless ($self->{BACKUP_DATA}{BACKUP_RESULT}) {
                # remove old dirs if backup was successfully done
                $oTargetPeer->removeOld($oSourcePeer->getValue('keep'), \@sBakBaseDirs);
            }
    
            $sSourceExt=~ s/^\./\-/;
            my $sCurrentLink= "current" . $hBaksetData->{BAKSET_EXT} . $sSourceExt;
            $oTargetPeer->unlink($sCurrentLink);
            $oTargetPeer->symlink($sBakDir, $sCurrentLink);
        };
    }

    # add finish function with final logging
    push @fFinish, sub {
        logger->decIndent();
        logger->info('Backup done at ' . strftime("%F %X", localtime) . ': ' . $sSourceName);
    };
    
    $self->{BACKUP_DATA}{FINISH_BACKUP}= \@fFinish;
    
    
    $self->{BACKUP_DATA}{BACKUP_RESULT}= $oSourcePeer->prepareBackup();
    return $self->{BACKUP_DATA}{BACKUP_RESULT};
}

sub _run {
    my $self= shift;

    $self->{BACKUP_DATA}{BACKUP_RESULT}= $self->{SOURCE}->run(
        $self->{TARGET},
        {
            DATA_DIR => $self->{TARGET}->getPath($self->{BACKUP_DATA}{BACKUP_DATA_DIR}),
            META_DIR => $self->{TARGET}->getPath($self->{BACKUP_DATA}{BACKUP_META_DIR}),
            OLD_DATA_DIRS => $self->{BACKUP_DATA}{OLD_BACKUP_DATA_DIRS},
            FILE_CALLBACK => $self->{BACKUP_DATA}{FILE_CALLBACK},
            STATISTICS_CALLBACK => sub {$self->setMetaBackupStatistics(@_)},
        },
    );
    $self->setMetaBackupResult($self->{BACKUP_DATA}{BACKUP_RESULT});
    return $self->{BACKUP_DATA}{BACKUP_RESULT};
}

sub _cleanup {
    my $self= shift;
    
    $_->() for (@{$self->{BACKUP_DATA}{FINISH_BACKUP}});
    return $self->{BACKUP_DATA}{BACKUP_RESULT};
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
        while ($sMetaVersion ne $self->METAVERSION()) {
            die "Internal error: Meta version \"$sMetaVersion\" has no convert function!" unless $hConvFuncs->{$sMetaVersion};
            my $sOldMetaVersion= $sMetaVersion;
            $sMetaVersion= $hConvFuncs->{$sMetaVersion}->($sDir);
            $self->_writeVersion($sDir, $sMetaVersion);
            logger->info("Converted backup directory from version \"$sOldMetaVersion\" to \"$sMetaVersion\".");
        }
    }
}

sub _buildDupMerge {
    my $self= shift;
    my $oTargetPeer= shift;
    my $refInodeStore= shift;
    my $aBakBaseDirs= shift;
    my $hTempFilesMap= shift || {};

    my $fAddDir;
    if ($oTargetPeer->isRemote()) {
        $fAddDir= sub {
            my $sBakBaseDir= shift;
            my $sRemoteFilesInodeDb= $oTargetPeer->getPath($sBakBaseDir . '/meta/files_inode.db');
            my $sDataDir= $oTargetPeer->getPath($sBakBaseDir . '/data');
            return unless $oTargetPeer->isFile($sRemoteFilesInodeDb) && $oTargetPeer->isDir($sDataDir);
            logger->verbose("Adding \"$sDataDir\".");
            my $sLocalFilesInodeDb= $oTargetPeer->getLocalFile($sRemoteFilesInodeDb, SUFFIX => '.files_inode.db');
            $hTempFilesMap->{$sRemoteFilesInodeDb}= $sLocalFilesInodeDb;
            ${$refInodeStore}->addDirectory($sDataDir, $sLocalFilesInodeDb);
        };
    }
    else {
        $fAddDir= sub {
            my $sBakBaseDir= shift;
            my $sFilesInodeDb= $oTargetPeer->getPath($sBakBaseDir . '/meta/files_inode.db');
            my $sDataDir= $oTargetPeer->getPath($sBakBaseDir . '/data');
            return unless $oTargetPeer->isFile($sFilesInodeDb) && $oTargetPeer->isDir($sDataDir);
            logger->verbose("Adding \"$sDataDir\".");
            ${$refInodeStore}->addDirectory($sDataDir, $sFilesInodeDb);
        };
    }
    return sub {
        logger->info("Start merging duplicates...");
        logger->incIndent();
        logger->verbose("Adding old backup dirs...");
        logger->incIndent();
        $fAddDir->($_) for (@$aBakBaseDirs);
        logger->decIndent();
        logger->verbose("done");

        my $dupMerge= Rabak::DupMerge->new({
            INODE_CACHE => ${$refInodeStore},
        });
        $dupMerge->dupMerge($oTargetPeer);

        logger->decIndent();
        logger->info("done");
    };
}

sub _getMetaVersionFile {
    my $self= shift;
    my $sDir= shift || '';
    return $sDir . '/meta/' . $METAFILENAMES{version};
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
    
    return if $self->{TARGET}->pretend();
    
    $self->_writeMetaFile($self->_getMetaVersionFile($sDir), $sVersion);
}

sub _writeMetaFile {
    my $self= shift;
    my $sMetaFile= shift;
    my @sContent= @_;
    
    $sMetaFile= ($self->{BACKUP_DATA}{BACKUP_META_DIR} || '.') . '/' . $sMetaFile unless $sMetaFile =~ /\//;
    $self->{TARGET}->unlink($sMetaFile);
    $self->{TARGET}->echo($sMetaFile, @sContent);
}

sub setMetaBackupResult {
    my $self= shift;
    my $sResult= shift;

    $self->_writeMetaFile($METAFILENAMES{result}, $sResult);
}

sub setMetaBackupError {
    my $self= shift;
    my $sError= shift;

    $self->_writeMetaFile($METAFILENAMES{error}, $sError);
}

sub setMetaBackupStatistics {
    my $self= shift;
    my @sStatistics= @_;

    $self->_writeMetaFile($METAFILENAMES{statistics}, @sStatistics);
}

1;
