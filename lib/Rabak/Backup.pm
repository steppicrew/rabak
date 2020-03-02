#!/usr/bin/perl

package Rabak::Backup;

# this class connects a target with a source

use warnings;
use strict;
#use vars qw(@ISA);

use Data::Dumper;
use Rabak::Log;
use Rabak::Util;
use POSIX qw(strftime);

sub new {
    my $class= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;

    my $self= {
        SOURCE => $oSourcePeer,
        TARGET => $oTargetPeer,
        PRETEND => $oSourcePeer->pretend(),
    };
    bless $self, $class;
}

sub Factory {
    my $class= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;
    
    my $sType= ucfirst lc $oSourcePeer->getValue("type");

    my $new;
    eval {
        require "Rabak/Backup/$sType.pm";
        my $sClass= "Rabak::Backup::$sType";
        $new= $sClass->new($oSourcePeer, $oTargetPeer);
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            logger->error("Backup type \"$sType\" is not defined: $@");
        }
        else {
            logger->error("An error occured: $@");
        }
        return undef;
    }

    return $new;
}

sub METAVERSION {1};

my %METAFILENAMES=(
    version    => 'Version',
    error      => 'Error',
    result     => 'Result',
    statistics => 'Statistics',
);

sub _pretend {
    my $self= shift;
    return $self->{PRETEND};
}

sub _getSource {
    my $self= shift;
    return $self->{SOURCE};
}

sub _getTarget {
    my $self= shift;
    return $self->{TARGET};
}

sub _getSourceValue {
    my $self= shift;
    
    return $self->_getSource()->getValue(@_);
}

sub sourcePropertyNames {
    my $self= shift;
    return @_;
}

sub run {
    my $self= shift;
    my $hJobData= shift;
    my $oSourceDataConf= shift;
    
    my $iResult= undef;
    
    $iResult= $_->() for $self->__buildBackupFuncs($hJobData, $oSourceDataConf);
    
    return $iResult;
}

sub _prepareBackup {
    my $self= shift;

    logger->info("Source: " . $self->_getSource()->getFullPath());
    logger->setPrefix($self->_getSourceValue("type"));
    return 0;
}
sub _finishBackup {
    my $self= shift;
    
    logger->setPrefix();
    $self->_getSource()->cleanupTempfiles();
}

sub sourceShow {
    return ();
}

sub __buildBackupFuncs {
    my $self= shift;
    my $hJobData= shift;
    my $oSourceDataConf= shift;

    my $oSourcePeer= $self->{SOURCE};
    my $oTargetPeer= $self->{TARGET};
    my $sSourceName= $oSourcePeer->getName() || $oSourcePeer->getFullPath();
    
    # set some pathes and ids ("vlrm"is "/var/lib/rabak/[mediaid]")
    my $sBackupUuid= Rabak::Util->CreateUuid();
    my $sVlrmBase= Rabak::Util->GetVlrDir();
    return () unless defined $sVlrmBase;
    
    $sVlrmBase.= '/' . $oTargetPeer->getUuid();
    my $sVlrmBakMetaDir= 'meta/' . strftime('%Y%m%d', localtime) . '/' . $sBackupUuid;
    my $sControllerPrefix= Rabak::Util->GetControllerUuid();
    return () unless defined $sControllerPrefix;
    $sControllerPrefix= 'meta/' . $sControllerPrefix . '.';

    # create locale peer object
    my $oVlrmPeer= Rabak::Peer->new();
    
    # init function list
    my @fBackup= ();
    
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
    
    $oSourceDataConf->setQuotedValue('time.start', Rabak::Util->GetTimeString());
    $oSourceDataConf->setQuotedValue('path', $oSourcePeer->getFullPath());
    $oSourceDataConf->setQuotedValue('target.fullpath', $oTargetPeer->getFullPath());
    $oSourceDataConf->setQuotedValue('target.datadir', $sBakDataDir);
    $oSourceDataConf->setQuotedValue('target.metadir', $sBakMetaDir);
    $oSourceDataConf->setQuotedValue('target.diskfree.start', scalar $oTargetPeer->getDf('-B1'));

    $self->_convertBackupDirs(\@sBakBaseDirs);

    logger->info("Backup \"$sBakDay$sSourceExt\" exists, using subset \"$sSourceSubdir\".") if $sSubSet;

    # create target directories
    $oTargetPeer->mkdir($sBakDir);
    $oTargetPeer->mkdir($sBakDataDir);
    $oTargetPeer->mkdir($sBakMetaDir);
    
    # create vlrmed dir
    $oVlrmPeer->mkdir("$sVlrmBase/$sVlrmBakMetaDir");
    # create symlink from (computer readable) meta dir to targets meta dir
    my $sSymlink= $sVlrmBakMetaDir;
    $sSymlink=~ s/\/[^\/]+$//;
    $sSymlink=~ s/[^\/]+/../g;
    $oTargetPeer->symlink("$sSymlink/$sBakMetaDir", $sVlrmBakMetaDir);
    
    $self->_writeVersion($sBakDir);
    
    my $iTotalBytes= 0;
    my $iTransferredBytes= 0;
    my $iTotalFiles= 0;
    my $iTransferredFiles= 0;
    my $iFailedFiles= 0;

    my $fStatisticCallback= sub {
        my @sStatText= @_;
        $oSourceDataConf->setQuotedValue('stats.text', join("\n", @sStatText));
    };
    my $fFailedFileCallback= sub { $iFailedFiles++; };
    my $fFileCallback;
    
    logger->info('Backup start at ' . strftime('%F %X', localtime) . ': ' . $sSourceName);
    logger->incIndent();
    my $iBackupResult= $self->_prepareBackup();

    # run backup
    push @fBackup, sub {
        $iBackupResult= $self->_run(
            {
                DATA_DIR => $oTargetPeer->getPath($sBakDataDir),
                OLD_DATA_DIRS => [map { $_ . '/data' } @sBakBaseDirs],
                FILE_CALLBACK => $fFileCallback,
                FAILED_FILE_CALLBACK => $fFailedFileCallback,
                STATISTICS_CALLBACK => $fStatisticCallback,
            },
        );
    } unless $iBackupResult;

    # start finish functions with cleaning up source
    push @fBackup, sub {
        $self->_finishBackup();
    };
    
    if ($oSourcePeer->getValue("inode_inventory")) {
        unless ($self->_pretend()) {
            # add finish function for inode inventory (and set per-file-callback function)
            my $sInodesDb= "$sVlrmBase/${sControllerPrefix}inodes.db";
            my $sFilesInodeDb=  "$sVlrmBase/$sVlrmBakMetaDir/files_inode.db";

            # create files on target if they don't exist to enable syncing meta data
            $oTargetPeer->createFile($sControllerPrefix . 'inodes.db');
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

                $fFileCallback= sub {
                    my $sFileName= shift;
                    my $sFlags= shift || '';
                    print $fh "$sFlags:$sFileName\n";
                };

                push @fBackup, sub {
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

# broken: @sBakBaseDirs should be a list of old backup objects            
#                if ($oSourcePeer->getValue('merge_duplicates')) {
#                    push @fBackup, $self->_buildDupMerge(
#                        $oTargetPeer, \$inodeStore, \@sBakBaseDirs, $sMetaDir,
#                    );
#                }

                push @fBackup, sub {
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

                $fFileCallback= sub {
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
            
                push @fBackup, sub {
                    # finish up previously nonexistant files
                    $fFileCallback->();
                };

# broken: @sBakBaseDirs should be a list of old backup objects            
#                if ($oSourcePeer->getValue('merge_duplicates')) {
#                    push @fBackup, $self->_buildDupMerge(
#                        $oTargetPeer, \$inodeStore, \@sBakBaseDirs, $sMetaDir,
#                    );
#                }
    
                push @fBackup, sub {
                    logger->verbose("Finishing information store...");
                    $inodeStore->finishInformationStore();
                    logger->verbose("done");
                };
	    }
        }
    }
    
    # add finish function to log backup result
    push @fBackup, sub {
        if ($iBackupResult) {
            logger->error("Backup failed: " . $oSourcePeer->getLastError());
            $iBackupResult= 9;
        }
        else {
            logger->info("Done!");
        }
    };

    # add finish function to update $oSourceDataConf
    push @fBackup, sub {
        $oSourceDataConf->setQuotedValue('time.end', Rabak::Util->GetTimeString());
        $oSourceDataConf->setQuotedValue('result', $iBackupResult);
        $oSourceDataConf->setQuotedValue('stats.total_bytes', $iTotalBytes);
        $oSourceDataConf->setQuotedValue('stats.transferred_bytes', $iTransferredBytes);
        $oSourceDataConf->setQuotedValue('stats.total_files', $iTotalFiles);
        $oSourceDataConf->setQuotedValue('stats.transferred_files', $iTransferredFiles);
        $oSourceDataConf->setQuotedValue('stats.failed_files', $iFailedFiles);
        $oSourceDataConf->setQuotedValue('target.diskfree.end', scalar $oTargetPeer->getDf('-B1'));
    };

    unless ($self->_pretend()) {
        # add finish function to remove old backups and symlink current directory
        push @fBackup, sub {
            unless ($iBackupResult) {
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
    push @fBackup, sub {
        logger->decIndent();
        logger->info('Backup done at ' . strftime("%F %X", localtime) . ': ' . $sSourceName);
    };
    
    # return function list and backup result as last result
    return @fBackup, sub { $iBackupResult };
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
    $sVersion=~ s/^(\S+)[\s\S]$/$1/;
    return $sVersion;
}

sub _writeVersion {
    my $self= shift;
    my $sDir= shift;
    my $sVersion= shift || $self->METAVERSION();
    
    return if $self->_pretend();
    
    $self->_writeMetaFile($self->_getMetaVersionFile($sDir), $sVersion);
}

sub _writeMetaFile {
    my $self= shift;
    my $sMetaFile= shift;
    my @sContent= @_;
    
    $self->{TARGET}->unlink($sMetaFile);
    $self->{TARGET}->echo($sMetaFile, @sContent);
}

1;
