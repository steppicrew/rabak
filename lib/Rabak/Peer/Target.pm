#!/usr/bin/perl

package Rabak::Peer::Target;

use warnings;
use strict;
no warnings 'redefine';

use Rabak::Log;
use Rabak::Mountable;
use Rabak::ConfFile;
use Rabak::InodeCache;
use Rabak::DupMerge;
use Rabak::Version;
use Rabak::Peer;
use POSIX qw(strftime);
use Data::Dumper;

use vars qw(@ISA);

@ISA = qw(Rabak::Peer);

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{MOUNTABLE}= Rabak::Mountable->new($self);
    $self->{UUID}= undef;

    return $self;
}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return (shift->SUPER::PropertyNames(), Rabak::Mountable->PropertyNames(), 'group', 'discfree_threshold');
}

sub mountable {
    my $self= shift;
    return $self->{MOUNTABLE};
}

sub _getDevConfFile {
    my $self= shift;
    return $self->getSwitch('dev_conf_file', "rabak.dev.cf");
}

# tests if device is mounted and is a valid rabak target
# valid rabak target devices always have a "rabak.dev.cf" file in root
# @param $sMountDevice
#   device to check
# @param $sMountDir
#   mount dir in fstab if $sMountDevice is not given
# @return
#   0 : don't know which device to check (set by SUPER)
#   1 : device is not mounted (set by SUPER)
#   2 : device is not valid
#   <path>: path the device is mounted at (set by SUPER)
#   
sub checkMount {
    my $self= shift;
    my $sMountDevice= shift;
    my $arMountMessages= shift;
    
    my $sMountPath= $self->mountable()->checkMount($sMountDevice, $arMountMessages);
    
    return $sMountPath if $sMountPath=~ /^\d+$/;

    my $sTargetValue= $self->getValue("group", "");
    
    my $sqTargetValue= quotemeta $sTargetValue;
    if (defined $self->getSwitch('targetvalue')) {
        $sTargetValue.= "." . $self->getSwitch('targetvalue');
        $sqTargetValue= quotemeta $sTargetValue;
    }
    else {
        $sqTargetValue.= '(\.\w+)?';
    }

    my $sDevConfFile= File::Spec->join($sMountPath, $self->_getDevConfFile());
    if ($self->isReadable("$sDevConfFile")) {
        if ($sTargetValue) {
            my $oDevConfFile= Rabak::ConfFile->new($self->getLocalFile($sDevConfFile, SUFFIX => '.dev.cf'));
            my $oDevConf= $oDevConfFile->conf();
            my $sFoundTargets = $oDevConf->getValue('targetvalues') || '';
            if (" $sFoundTargets " =~ /\s$sqTargetValue\s/) {
                push @$arMountMessages, logger->info("Target value \"$sTargetValue\" found on device \"$sMountDevice\"");
            }
            else {
                push @$arMountMessages, logger->warn("Target value \"$sTargetValue\" not found on device \"$sMountDevice\" (found: \"" .
                    join("\", \"", split(/\s+/, $sFoundTargets)) .
                    "\")");
                return 2;
            }
        }
        else { # no target group specified -> if conf file is present, this is our target
            push @$arMountMessages, logger->info("No target group specified but '$sDevConfFile' exists");
        }
    }
    else {
        push @$arMountMessages, logger->info("Device config file \"".$self->getFullPath($sDevConfFile)."\" not found on device \"$sMountDevice\"");
        return 2;
    }
    return $sMountPath;
}

sub mountErrorIsFatal {
    my $self= shift;
    my $iMountResult= shift;

    return $iMountResult;
}

sub getDf {
    my $self= shift;
    my @sParams= @_;
    
    my $sDfResult = $self->df(undef, @sParams);

    unless ($sDfResult =~ /^\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+/m && $1 > 100) {
        logger->error("Could not get free disc space!", $sDfResult);
        return (undef, undef, undef);
    }
    return ($1, $2, $3) if wantarray;
    return $2;
}

sub _checkDf {
    my $self= shift;

    my $sSpaceThreshold= $self->getValue('discfree_threshold');
    return undef unless $sSpaceThreshold;

    my $iStValue= $sSpaceThreshold =~ /\b([\d\.]+)/ ? $1 : 0;
    my $sStUnit= 'K';
    $sStUnit = uc($1) if $sSpaceThreshold =~ /$iStValue\s*([gmkb\%])/i;
    my ($iDfSize, $iDfAvail) = $self->getDf('-k');
    $iDfAvail /= $iDfSize / 100 if $sStUnit eq '%';
    $iDfAvail >>= 20            if $sStUnit eq 'G';
    $iDfAvail >>= 10            if $sStUnit eq 'M';
    $iDfAvail <<= 10            if $sStUnit eq 'B';
    if ($iStValue > $iDfAvail) {
        $iDfAvail= int($iDfAvail * 100) / 100;
        return [
                "The free space on your target \"" . $self->getFullPath . "\" has dropped ",
                "below $iStValue$sStUnit to $iDfAvail$sStUnit.",
        ];
    }
    return undef;
}

sub removeOld {
    my $self= shift;
    my $iKeep= shift;
    my $aOldBackupDirs= shift;
    
    # TODO: keep should count only successful backups (status should be in meta dir)
    
    return unless $iKeep;

    logger->info(
        "Keeping last " . ($iKeep == 1 ? "version" : "$iKeep versions")
    );

    logger->incIndent();
    my @sBakDir= @$aOldBackupDirs;
    my $sqPath= quotemeta $self->getPath();
    my $iCount= 0;
    foreach my $sDir (@sBakDir) {
        $sDir= $self->getPath($sDir);
        unless ($sDir=~ /^$sqPath/) {
            logger->error("Directory '$sDir' not beneath Target Dir. Not removing.");
            next;
        }
        # remove directories only
        next unless $self->isDir($sDir);
        # skip first $iKeep nonempty directories
        if ($self->glob("$sDir/*")) {
            next if $iKeep-- > 0;
        }
        logger->verbose("Removing \"$sDir\"");
        $self->rmtree($sDir);
        if ($self->getLastExit()) {
            logger->error($self->getLastError()) ;
        }
        else {
            $iCount++;
        }
        my $sInodeDb= $sDir;
        $sInodeDb=~ s/\/+$//;
        $sInodeDb.= ".file_inode.db";
        $self->unlink($sInodeDb) if $self->isFile($sInodeDb);
    }
    logger->decIndent();
    logger->info("Number of removed backups: $iCount");
}

sub _prepare {
    my $self= shift;
    my $asJobExts= shift;

    my $mountable= $self->mountable();

    # mount all target mount objects
    my @sMountMessage= ();
    my $iMountResult= $mountable->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        logger->error("There was at least one fatal mount error on target. Job skipped.");
        logger->error(@sMountMessage);
        return { ERROR => -3 };
    }
    logger->log(@sMountMessage);

    # check target dir
    unless ($self->isDir()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->getValue("path")."\" is not a directory. Job skipped.");
        return { ERROR => -1 };
    }
    unless ($self->isWritable()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->getValue("path")."\" is not writable. Job skipped.");
        return { ERROR => -2 };
    }
    return undef;
}

# return meta dir of Job
sub GetMetaDir {
    return '.meta';
}

sub getUuid {
    my $self= shift;
    return $self->{UUID};
}

# prepare target for backup
# 1. mounts all target mount objects
# 2. checks existance and permissions of target's directory
# 3. creates Job's target directory
# sets some session data
sub prepareForBackup {
    my $self= shift;
    my $asJobExts= shift;

    my $hResult= $self->_prepare($asJobExts);
    return $hResult if $hResult;

    my $sJobExt= $asJobExts->[0];
    my $aJobTime= [ localtime ];
    my $sJobDir= strftime("%Y-%m", @$aJobTime) . $sJobExt;
    my $sJobMeta= $self->GetMetaDir();

    my $sDevConfFile= $self->getPath($self->_getDevConfFile());
    my $sLocalDevConfFile= $sDevConfFile;
    my $oDevConf;
    if ($self->isFile($sDevConfFile)) {
        $sLocalDevConfFile= $self->getLocalFile($sDevConfFile, SUFFIX => '.dev.cf');
        my $oDevConfFile= Rabak::ConfFile->new($sLocalDevConfFile);
        $oDevConf= $oDevConfFile->conf();
        $self->{UUID}= $oDevConf->getValue('uuid');
    }
    else {
        $sLocalDevConfFile= $self->localTempfile(SUFFIX => '.dev.cf') if $self->isRemote();
        $oDevConf= Rabak::Conf->new('*');
    }
    unless ($self->{UUID}) {
        # create new uuid and write into target's directory
        $self->{UUID}= $self->CreateUuid();
        $oDevConf->setQuotedValue('uuid', $self->{UUID});
        $oDevConf->writeToFile($sLocalDevConfFile);
        $self->copyLocalFileToRemote($sLocalDevConfFile, $sDevConfFile);
    }

    $self->mkdir($sJobDir);
    $self->mkdir($sJobMeta);

    # if ($self->isWritable("$sJob/target.cf")) {
    #     $oConf= new Rabak::ConfFile();
    # }

    return {
        JOB_EXT => $sJobExt,     # path extension for current Job
        ALL_JOB_EXTS => $asJobExts,  # path extensions for this and all previous jobs
        JOB_DIR => $sJobDir, # job's directory (relative to target dir)
        JOB_TIME => $aJobTime,   # date of job start
        ALL_JOB_DIRS => $self->_getAllBakdirs(),  # hash of all job dirs
        JOB_META_DIR => $sJobMeta,
    };
}

sub finish {
    my $self= shift;
    
    $self->cleanupTempfiles();

    my $mountable= $self->mountable();

    # unmount all target mounts
    $mountable->unmountAll();
}

sub finishBackup {
    my $self= shift;
    my $hJobData= shift;
    my $fCallback= shift;

    my $aDf = $self->_checkDf();
    if (defined $aDf) {
        logger->warn(join "", @$aDf);
        my $sHostName= $self->getValue("host") || $self->cmdData("hostname");
        logger->mailWarning("disc space too low on ${sHostName}'s target dir \"" . $self->absPath($self->getPath()) . "\"",
            "Rabak Version " . VERSION() . " on \"" . $self->cmdData("hostname") . "\" as user \"" . $self->cmdData("user") . "\"",
            "Command line: " . $self->cmdData("command_line"),
            "#"x80,
            @$aDf
        );
    }
    
    $fCallback->() if $fCallback;

    $self->_closeLogging();
    
    $self->finish();
    
    $self->{JOB_DATA}= undef;
    return 0;
}

sub _getLogFileInfo {
    my $self= shift;

    my $aJobTime= shift;
    my $sJobDir= shift;
    my $sJobExt= shift;

    my $sLogDir= strftime("%Y-%m", @$aJobTime) . "-log";
    my $sLogFile= $sLogDir . '/' . strftime("%Y-%m-%d", @$aJobTime) . $sJobExt . '.log';

    return {
        DIR => $sLogDir,
        FILE => $sLogFile,
        FULL_FILE => $self->getPath($sLogFile),
    };
}

sub initLogging {
    my $self= shift;
    my $hJobData= shift || {};

    my $aJobTime= $hJobData->{JOB_TIME};
    my $sJobDir= $hJobData->{JOB_DIR};
    my $sJobExt= $hJobData->{JOB_EXT};

    my $hInfo= $self->_getLogFileInfo($aJobTime, $sJobDir, $sJobExt);

    my $sLogDir= $hInfo->{DIR};
    my $sLogFile= $hInfo->{FILE};
    my $sLogFilePath= $hInfo->{FULL_FILE};

    my $sJobMonth= strftime("%Y-%m", @$aJobTime);

    unless ($self->pretend()) {
        $self->mkdir($sLogDir);
        my $sLogLink= $sJobDir . '/' . strftime("%Y-%m-%d", @$aJobTime) . $sJobExt . '.log';

        my $sError= logger->open($sLogFilePath, $self);
        if ($sError) {
            logger->warn("Can't open log file \"$sLogFilePath\" ($sError). Going on without...");
        }
        else {
            $self->symlink("../$sLogFile", $sLogLink);
            my $sCurrentLogFileName= 'current-log' . $sJobExt;
            $self->unlink($sCurrentLogFileName);
            $self->symlink($sLogFile, $sCurrentLogFileName);
        }
    }
    logger->info("Logging to: $sLogFilePath");
    logger->info("", "**** Only pretending, no changes are made! ****", "") if $self->pretend();
}

sub _closeLogging {
    my $self= shift;

    logger->close();
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};

    my @sSuperResult= @{$self->SUPER::show($hConfShowCache)};
    push @sSuperResult, @{$self->mountable()->show($hConfShowCache)};
    return [] unless @sSuperResult;
    
    return [
        "",
        "#" . "=" x 79,
        "# Target \"" . $self->getShowName() . "\": " . $self->getFullPath(),
        "#" . "=" x 79,
        @sSuperResult
    ];
}

sub getPath {
    my $self= shift;
    return $self->mountable()->getPath(@_);
}

sub _getAllBakdirs {
    my $self= shift;

    # get recursive file listing for 1 extra level
    my %hDirs= $self->getDirRecursive(undef, 1);

    my %hResult= ();

    # hDirs is of the format: { dir => { file => 1 }, file, ... }
    # The next three lines iterates over the values of the outer hash, skips the files, takes the dirs.
    # These dirs are iterated over and all keys (=files) are collected. voila!
    map {
        my $hDir= $_;
        map {
            $hResult{$_}= {
                path => $1,
                job_ext => $2,
                date => $3,
                year => $4,
                month => $5,
                day => $6,
                subset => $8 ? "_$8" : '',
                source_ext => (defined $9 ? $9 : ''),
            } if /(.*)\/\d{4}-\d\d(\..+)\/((\d{4})\-(\d\d)\-(\d\d))([\-_](\d{3,4}))?(\..+)?$/;
        } grep { ref $$hDir{$_} eq 'HASH' } keys %$hDir;
    } grep { ref $_ } values %hDirs;

    # decremental backup

    return \%hResult;
}

sub getBakdirsByExts {
    my $self= shift;
    my $asJobExts= shift;
    my $asSourceExts= shift;
    my $hDirs= shift || $self->_getAllBakdirs();

    my $i= 1;
    my %hJobExts=    map { $_ => $i++ } @$asJobExts;
    my %hSourceExts= map { $_ => $i++ } @$asSourceExts;

    my @sBakDirs= ();

    my $cmp= sub {
        my $ad= $hDirs->{$a};
        my $bd= $hDirs->{$b};
        return
            $bd->{date} cmp $ad->{date}
                || $hJobExts{$ad->{job_ext}} cmp $hJobExts{$bd->{job_ext}}
                || $hSourceExts{$ad->{source_ext}} cmp $hSourceExts{$bd->{source_ext}}
                || $bd->{subset} cmp $ad->{subset}
        ;
    };

    # go away if you don't grok this:
    @sBakDirs= sort $cmp grep {
        my $hDir= $hDirs->{$_};
        exists $hJobExts{$hDir->{job_ext}} && exists $hSourceExts{$hDir->{source_ext}}
    } keys %$hDirs;

    return @sBakDirs;
}

1;
