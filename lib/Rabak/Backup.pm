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
    my $hJobData= shift;
    my $oSourceDataConf= shift;
    
    $self->_run() unless $self->_setup($hJobData, $oSourceDataConf);
    return $self->_cleanup();
}

sub _setup {
    my $self= shift;
    my $hJobData= shift;
    my $oSourceDataConf= shift;

    my $oSourcePeer= $self->{SOURCE};
    my $oTargetPeer= $self->{TARGET};
    
    $oSourceDataConf->setValue('time.start', Rabak::Conf->GetTimeString());
    $oSourceDataConf->setValue('path', $oSourcePeer->getFullPath());;

    my $sSourceName= $oSourcePeer->getName() || $oSourcePeer->getFullPath();
    logger->info('Backup start at ' . strftime('%F %X', localtime) . ': ' . $sSourceName);
    logger->incIndent();

    # prepare target for backup
    my $asSourceExts= Rabak::Job->GetAllPathExtensions($oSourcePeer);
    # TODO: may be we only need "%d" as $sBakDay?
    my $sBakDay= strftime("%Y-%m-%d", @{$hJobData->{JOB_TIME}});

    my $hDirs= $hJobData->{ALL_JOB_DIRS};

    my @sBakBaseDirs= $oTargetPeer->getBakdirsByExts(
        $hJobData->{ALL_JOB_EXTS},
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
    my $sBakDir= $hJobData->{JOB_DIR} . '/' . $sSourceSubdir;
    my $sBakDataDir= $sBakDir . '/data';
    my $sBakMetaDir= $sBakDir . '/meta';
    
    $oSourceDataConf->setQuotedValue('target.fullpath', $oTargetPeer->getFullPath());
    $oSourceDataConf->setQuotedValue('target.datadir', $sBakDataDir);
    $oSourceDataConf->setQuotedValue('target.metadir', $sBakMetaDir);
    $oSourceDataConf->setQuotedValue('target.diskfree.start', scalar $oTargetPeer->getDf('-B1'));

    $self->_convertBackupDirs(\@sBakBaseDirs);

    $self->{BACKUP_DATA}{OLD_BACKUP_DATA_DIRS}= [map { $_ . '/data' } @sBakBaseDirs];
    $self->{BACKUP_DATA}{BACKUP_DATA_DIR}= $sBakDataDir;
    $self->{BACKUP_DATA}{BACKUP_META_DIR}= $sBakMetaDir;
    
    logger->info("Backup \"$sBakDay$sSourceExt\" exists, using subset \"$sSourceSubdir\".") if $sSubSet;

    $oTargetPeer->mkdir($sBakDir);
    $oTargetPeer->mkdir($sBakDataDir);
    $oTargetPeer->mkdir($sBakMetaDir);
    $self->_writeVersion($sBakDir);
    
    my $iTotalBytes= 0;
    my $iTransferredBytes= 0;
    my $iTotalFiles= 0;
    my $iTransferredFiles= 0;
    my $iFailedFiles= 0;

    $self->{BACKUP_DATA}{STATISTICS_CALLBACK}= sub {
        my @sStatText= @_;
        $oSourceDataConf->setQuotedValue('stats.text', join("\n", @sStatText));
    };
    $self->{BACKUP_DATA}{FAILED_FILE_CALLBACK}= sub { $iFailedFiles++; };
    
    ########################################################
    # set cleanup chain
    ########################################################
    
    # start finish functions with cleaning up source
    my @fFinish= (
        sub {$oSourcePeer->finishBackup($self->{BACKUP_DATA}{BACKUP_RESULT})},
    );
    
    unless ($oTargetPeer->pretend()) {
        # add finish function for inode inventory (and create per-file-callback function)
        my $sMetaDir= Rabak::Job->GetMetaBaseDir($oTargetPeer->getUuid());
        my $sInodesDb= "$sMetaDir/inodes.db";
        my $sFilesInodeDb=  Rabak::Job->GetMetaBaseDir(
            $oTargetPeer->getUuid() . '/' . $oTargetPeer->GetMetaDir() . '/' . $sBakMetaDir
        ) . '/files_inode.db';

        # create files on target if they don't exist to enable syncing meta data
        $oTargetPeer->createFile($hJobData->{JOB_META_DIR} . '/inodes.db');
        $oTargetPeer->createFile($sBakMetaDir . '/files_inode.db');
        
        my $inodeStore;
        my $fPrepareInodeStore= sub {
            logger->verbose("Preparing information store for inode inventory...");
            logger->incIndent();
            $inodeStore= Rabak::InodeCache->new({
                inodes_db => $sInodesDb,
            }); 
            $inodeStore->prepareInformationStore(
                $oTargetPeer->getPath($sBakDataDir),
                $sFilesInodeDb,
            );
            logger->decIndent();
            logger->verbose("done");
        };
        
        if ($oTargetPeer->isRemote()) {
            # special handling for remote targets (see idea below)
            my ($fh, $sFileListFile)= $oTargetPeer->localTempfile(SUFFIX => '.filelist.txt');

            $self->{BACKUP_DATA}{FILE_CALLBACK}= sub {
                my $sFileName= shift;
                my $sFlags= shift || '';
                print $fh "$sFlags:$sFileName\n";
            };

            push @fFinish, sub {
                close $fh;
                
                $fPrepareInodeStore->();
                
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
                            my @sParams= split /\:/, $sLine, 15;        #/ # result is 14 lstat values, flags, file name 
                            if (scalar @sParams < 15) {
                                logger->error("Error parsing inventory data (\"$sLine\").");
                                next;
                            }
                            my $sFileName= pop @sParams;
                            my $sFlags= pop @sParams;
                            $inodeStore->addFile($sFileName, @sParams);
                            $iTotalBytes+= $sParams[7];
                            $iTotalFiles++;
                            unless ($sFlags=~ /h/) {
                                $iTransferredBytes+= $sParams[7];
                                $iTransferredFiles++;
                            }
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
                        my ($sFlags, $sFileName)= split /\:/, $_, 2;
                        print join(":", lstat $sFileName, $sFlags, $sFileName), "\n";
                    }',
                    undef, undef, \%Handles,
                );
                close $fh;
            };
            
            if ($oSourcePeer->getValue('merge_duplicates')) {
                push @fFinish, $self->_buildDupMerge(
                    $oTargetPeer, \$inodeStore, \@sBakBaseDirs, $sMetaDir,
                );
            }

            push @fFinish, sub {
                logger->verbose("Finishing information store...");
                logger->incIndent();
                $inodeStore->finishInformationStore();
                logger->decIndent();
                logger->verbose("done");
            };
        }
        else {
            # handle inode inventory for local targets
            $fPrepareInodeStore->();
            
            my @sInventFiles= ();

            $self->{BACKUP_DATA}{FILE_CALLBACK}= sub {
                # add only existant files, remember nonexistant (files may be created after logging)
                my $sFile= shift;
                my $sFlags= shift || '';
                push @sInventFiles, [$sFile, $sFlags] if defined $sFile;
                my $count= scalar @sInventFiles;
                while ($count--) {
                    ($sFile, $sFlags)= @{ shift @sInventFiles };
                    if (-e $sFile) {
                        my @sStat= lstat $sFile;
                        $inodeStore->addFile($sFile, @sStat);
                        $iTotalBytes+= $sStat[7];
                        $iTotalFiles++;
                        unless ($sFlags=~ /h/) {
                            $iTransferredBytes+= $sStat[7];
                            $iTransferredFiles++;
                        }
                        next;
                    }
                    push @sInventFiles, [$sFile, $sFlags];
                }
                return scalar @sInventFiles;
            };
            
            push @fFinish, sub {
                # finish up previously nonexistant files
                $self->{BACKUP_DATA}{FILE_CALLBACK}->();
            };

            if ($oSourcePeer->getValue('merge_duplicates')) {
                push @fFinish, $self->_buildDupMerge(
                    $oTargetPeer, \$inodeStore, \@sBakBaseDirs, $sMetaDir,
                );
            }
    
            push @fFinish, sub {
                logger->verbose("Finishing information store...");
                $inodeStore->finishInformationStore();
                logger->verbose("done");
            };
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

    # add finish function to update $oSourceDataConf
    push @fFinish, sub {
        $oSourceDataConf->setQuotedValue('time.end', Rabak::Conf->GetTimeString());
        $oSourceDataConf->setQuotedValue('result', $self->{BACKUP_DATA}{BACKUP_RESULT});
        $oSourceDataConf->setQuotedValue('stats.total_bytes', $iTotalBytes);
        $oSourceDataConf->setQuotedValue('stats.transferred_bytes', $iTransferredBytes);
        $oSourceDataConf->setQuotedValue('stats.total_files', $iTotalFiles);
        $oSourceDataConf->setQuotedValue('stats.transferred_files', $iTransferredFiles);
        $oSourceDataConf->setQuotedValue('stats.failed_files', $iFailedFiles);
        $oSourceDataConf->setQuotedValue('target.diskfree.end', scalar $oTargetPeer->getDf('-B1'));
    };

    unless ($oTargetPeer->pretend()) {
        # add finish function to remove old backups and symlink current directory
        push @fFinish, sub {
            unless ($self->{BACKUP_DATA}{BACKUP_RESULT}) {
                # remove old dirs if backup was successfully done
                $oTargetPeer->removeOld($oSourcePeer->getValue('keep'), \@sBakBaseDirs);
            }
    
            $sSourceExt=~ s/^\./\-/;
            my $sCurrentLink= "current" . $hJobData->{JOB_EXT} . $sSourceExt;
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
            OLD_DATA_DIRS => $self->{BACKUP_DATA}{OLD_BACKUP_DATA_DIRS},
            FILE_CALLBACK => $self->{BACKUP_DATA}{FILE_CALLBACK},
            STATISTICS_CALLBACK => $self->{BACKUP_DATA}{STATISTICS_CALLBACK},
        },
    );
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
    my $sMetaDir= shift;

    return sub {
        logger->info("Start merging duplicates...");
        logger->incIndent();
        logger->verbose("Adding old backup dirs...");
        logger->incIndent();
        for my $sBakBaseDir (@$aBakBaseDirs) {
            my $sFilesInodeDb= $sMetaDir . '/' . $oTargetPeer->GetMetaDir() ."/$sBakBaseDir/meta/files_inode.db";
            my $sDataDir= $oTargetPeer->getPath($sBakBaseDir . '/data');
            next unless $oTargetPeer->isFile($sFilesInodeDb) && $oTargetPeer->isDir($sDataDir);
            logger->verbose("Adding \"$sDataDir\".");
            ${$refInodeStore}->addDirectory($sDataDir, $sFilesInodeDb);
        }
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

1;
