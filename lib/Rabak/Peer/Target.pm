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
use Data::UUID;

use vars qw(@ISA);

@ISA = qw(Rabak::Peer);

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{MOUNTABLE}= Rabak::Mountable->new($self);

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

sub _checkDf {
    my $self= shift;

    my $sSpaceThreshold= $self->getValue('discfree_threshold');
    return undef unless $sSpaceThreshold;

    my $iStValue= $sSpaceThreshold =~ /\b([\d\.]+)/ ? $1 : 0;
    my $sStUnit= 'K';
    $sStUnit = uc($1) if $sSpaceThreshold =~ /$iStValue\s*([gmkb\%])/i;
    my $sDfResult = $self->df(undef, '-k');

    unless ($sDfResult =~ /^\S+\s+(\d+)\s+\d+\s+(\d+)\s+/m && $1 > 100) {
        logger->error("Could not get free disc space!", $sDfResult);
        return undef;
    }
    my ($iDfSize, $iDfAvail) = ($1, $2);
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
    my $asBaksetExts= shift;

    my $mountable= $self->mountable();

    # mount all target mount objects
    my @sMountMessage= ();
    my $iMountResult= $mountable->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        logger->error("There was at least one fatal mount error on target. Backup set skipped.");
        logger->error(@sMountMessage);
        return { ERROR => -3 };
    }
    logger->log(@sMountMessage);

    # check target dir
    unless ($self->isDir()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->getValue("path")."\" is not a directory. Backup set skipped.");
        return { ERROR => -1 };
    }
    unless ($self->isWritable()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->getValue("path")."\" is not writable. Backup set skipped.");
        return { ERROR => -2 };
    }
    return undef;
}

# return meta dir of bakset
sub GetMetaDir {
    return '.meta';
}

# prepare target for backup
# 1. mounts all target mount objects
# 2. checks existance and permissions of target's directory
# 3. creates bakset's target directory
# sets some session data
sub prepareForBackup {
    my $self= shift;
    my $asBaksetExts= shift;
    my $hSessionData= shift;

    my $hResult= $self->_prepare($asBaksetExts);
    return $hResult if $hResult;

    my $sBaksetExt= $asBaksetExts->[0];
    my $aBaksetTime= [ localtime ];
    my $sBaksetDir= strftime("%Y-%m", @$aBaksetTime) . $sBaksetExt;
    my $sBaksetMeta= $self->GetMetaDir();

    my $sDevConfFile= $self->_getDevConfFile();
    my $sUUID;
    if ($self->isFile($sDevConfFile)) {
        my $oDevConfFile= Rabak::ConfFile->new($self->getLocalFile($sDevConfFile, SUFFIX => '.dev.cf'));
        my $oDevConf= $oDevConfFile->conf();
        $sUUID= $oDevConf->getValue('uuid');
    }
    unless ($sUUID) {
        $sUUID= Data::UUID->new()->create_str();
        # TODO: we need a ConfFile->write()
        $self->echo($sDevConfFile, '', '[]', "uuid = $sUUID");
    }
    $hSessionData->{target}= {
        'uuid' => $sUUID,
    };

    $self->mkdir($sBaksetDir);
    $self->mkdir($sBaksetMeta);

    # if ($self->isWritable("$sBakset/target.cf")) {
    #     $oConf= new Rabak::ConfFile();
    # }

    return {
        BAKSET_EXT => $sBaksetExt,     # path extension for current bakset
        ALL_BAKSET_EXTS => $asBaksetExts,  # path extensions for this and all previous backsets
        BAKSET_DIR => $sBaksetDir, # back set's directory (relative to target dir)
        BAKSET_TIME => $aBaksetTime,   # date of bak set start
        ALL_BAKSET_DIRS => $self->_getAllBakdirs(),  # hash of all bak set dirs
        BAKSET_META_DIR => $sBaksetMeta,
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
    my $hBaksetData= shift;
    my $hSessionData= shift;

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

    $self->_closeLogging();
    
    if ($hBaksetData->{BAKSET_META_DIR}) {
        my $sFileName= $hBaksetData->{BAKSET_META_DIR} . '/session.'
            . $hSessionData->{time}{start} . '.'
            . $hSessionData->{time}{end}
            . $hBaksetData->{BAKSET_EXT};
        $self->echo($sFileName, Data::Dumper->Dump([$hSessionData], ['session']));
    }
    
    $self->finish();
    
    $self->{BAKSET_DATA}= undef;
    return 0;
}

sub _getLogFileInfo {
    my $self= shift;

    my $aBaksetTime= shift;
    my $sBaksetDir= shift;
    my $sBaksetExt= shift;

    my $sLogDir= strftime("%Y-%m", @$aBaksetTime) . "-log";
    my $sLogFile= $sLogDir . '/' . strftime("%Y-%m-%d", @$aBaksetTime) . $sBaksetExt . '.log';

    return {
        DIR => $sLogDir,
        FILE => $sLogFile,
        FULL_FILE => $self->getPath($sLogFile),
    };
}

sub initLogging {
    my $self= shift;
    my $hBaksetData= shift || {};

    my $aBaksetTime= $hBaksetData->{BAKSET_TIME};
    my $sBaksetDir= $hBaksetData->{BAKSET_DIR};
    my $sBaksetExt= $hBaksetData->{BAKSET_EXT};

    my $hInfo= $self->_getLogFileInfo($aBaksetTime, $sBaksetDir, $sBaksetExt);

    my $sLogDir= $hInfo->{DIR};
    my $sLogFile= $hInfo->{FILE};
    my $sLogFilePath= $hInfo->{FULL_FILE};

    my $sBaksetMonth= strftime("%Y-%m", @$aBaksetTime);

    unless ($self->pretend()) {
        $self->mkdir($sLogDir);
        my $sLogLink= $sBaksetDir . '/' . strftime("%Y-%m-%d", @$aBaksetTime) . $sBaksetExt . '.log';

        my $sError= logger->open($sLogFilePath, $self);
        if ($sError) {
            logger->warn("Can't open log file \"$sLogFilePath\" ($sError). Going on without...");
        }
        else {
            $self->symlink("../$sLogFile", $sLogLink);
            my $sCurrentLogFileName= 'current-log' . $sBaksetExt;
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
                set_ext => $2,
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
    my $asSetExts= shift;
    my $asSourceExts= shift;
    my $hDirs= shift || $self->_getAllBakdirs();

    my $i= 1;
    my %hSetExts=    map { $_ => $i++ } @$asSetExts;
    my %hSourceExts= map { $_ => $i++ } @$asSourceExts;

    my @sBakDirs= ();

    my $cmp= sub {
        my $ad= $hDirs->{$a};
        my $bd= $hDirs->{$b};
        return
            $bd->{date} cmp $ad->{date}
                || $hSetExts{$ad->{set_ext}} cmp $hSetExts{$bd->{set_ext}}
                || $hSourceExts{$ad->{source_ext}} cmp $hSourceExts{$bd->{source_ext}}
                || $bd->{subset} cmp $ad->{subset}
        ;
    };

    # go away if you don't grok this:
    @sBakDirs= sort $cmp grep {
        my $hDir= $hDirs->{$_};
        exists $hSetExts{$hDir->{set_ext}} && exists $hSourceExts{$hDir->{source_ext}}
    } keys %$hDirs;

    return @sBakDirs;
}

1;
