#!/usr/bin/perl

package RabakLib::Peer::Target;

use warnings;
use strict;
no warnings 'redefine';

use RabakLib::Log;
use RabakLib::ConfFile;
use RabakLib::InodeCache;
use POSIX qw(strftime);
use Data::Dumper;

use vars qw(@ISA);

@ISA = qw(RabakLib::Peer);

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{MOUNTABLE}= RabakLib::Mountable->new($self);
    $self->{SOURCE_DATA}= undef;    
    $self->{BAKSET_DATA}= undef;    

    return $self;
}

sub mountable {
    my $self= shift;
    return $self->{MOUNTABLE};
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

    my $sTargetValue= $self->get_value("group", "");
    
    my $sqTargetValue= quotemeta $sTargetValue;
    if (defined $self->get_switch('targetvalue')) {
        $sTargetValue.= "." . $self->get_switch('targetvalue');
        $sqTargetValue= quotemeta $sTargetValue;
    }
    else {
        $sqTargetValue.= '(\.\w+)?';
    }

    my $sDevConfFile= File::Spec->join($sMountPath, $self->get_switch('dev_conf_file', "rabak.dev.cf"));
    if ($self->isReadable("$sDevConfFile")) {
        if ($sTargetValue) {
            my $oDevConfFile= RabakLib::ConfFile->new($self->getLocalFile($sDevConfFile));
            my $oDevConf= $oDevConfFile->conf();
            my $sFoundTargets = $oDevConf->get_value('targetvalues') || '';
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

sub checkDf {
    my $self= shift;

    my $sSpaceThreshold= $self->get_value('discfree_threshold');
    return undef unless $sSpaceThreshold;

    my $iStValue= $sSpaceThreshold =~ /\b([\d\.]+)/ ? $1 : 0;
    my $sStUnit= 'K';
    $sStUnit = uc($1) if $sSpaceThreshold =~ /$iStValue\s*([gmkb\%])/i;
    my $sDfResult = $self->df(undef, "-k");

    unless ($sDfResult =~ /^\S+\s+(\d+)\s+\d+\s+(\d+)\s+/m) {
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
        return ["The free space on your target \"" . $self->getFullPath . "\" has dropped",
                "below $iStValue$sStUnit to $iDfAvail$sStUnit."];
    }
    return undef;
}

sub remove_old {
    my $self= shift;
    my $iKeep= $self->getSourceKeep();
    
    return unless $iKeep;

    logger->info("Keeping last $iKeep versions");

    logger->incIndent();
    my @sBakDir= @{$self->getOldBakDirs()};
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
        if ($self->get_last_exit()) {
            logger->error($self->get_last_error()) ;
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

sub inodeInventory {
    my $self= shift;
    
    return 1 unless $self->getSourceInventory();
    if ($self->is_remote()) {
        logger->error('Inode inventory is supported only at local targets!');
        return 1;
    }
    my $inodeCache= new RabakLib::InodeCache(
        {
            dirs => [$self->getPath($self->getBakDir())],
            base_dir => $self->getPath(),
        }
    );
    logger->info("Collecting inode information");
    logger->incIndent();
    my $iResult= $inodeCache->collect();
    logger->decIndent();
    logger->info("done");
    return $iResult;
}

sub getBackupData {
    my $self= shift;
    my $sKey= shift;
    my $sProperty= shift;
    die "Internal error: {$sKey} is not set! Please file a bug report!" unless defined $self->{$sKey};
    die "Internal error: {$sKey}{$sProperty} is not set! Please file a bug report!" unless exists $self->{$sKey}{$sProperty};
    return $self->{$sKey}{$sProperty};
}

sub getBaksetData { 
    my $self= shift;
    my $sProperty= shift;
    return $self->getBackupData("BAKSET_DATA", $sProperty);
}
sub getBaksetExt    { shift()->getBaksetData("BAKSETEXT") }
sub getBaksetExts   { shift()->getBaksetData("BAKSETEXTS") }
sub getBaksetDir    { shift()->getBaksetData("BAKSETDIR") }
sub getBaksetMonth  { shift()->getBaksetData("BAKSETMONTH") }
sub getBaksetDay    { shift()->getBaksetData("BAKSETDAY") }
sub getBakDirs      { shift()->getBaksetData("BAKDIRS") }

sub getSourceData {
    my $self= shift;
    my $sProperty= shift;
    return $self->getBackupData("SOURCE_DATA", $sProperty);
}
sub getOldBakDirs   { shift()->getSourceData("OLD_BAKDIRS") }
sub getSubset       { shift()->getSourceData("SUBSET") }
sub getSourceSubdir { shift()->getSourceData("SOURCESUBDIR") }
sub getSourceSet    { shift()->getSourceData("SOURCESET") }
sub getSourceExt    { shift()->getSourceData("SOURCEEXT") }
sub getSourceKeep   { shift()->getSourceData("SOURCEKEEP") }
sub getSourceInventory { shift()->getSourceData("SOURCEINVENTORY") }
sub getBakDir       { shift()->getSourceData("BAKDIR") }
sub getAbsBakDir {
    my $self= shift;
    $self->getPath($self->getBakDir());
}

sub prepareBackup {
    my $self= shift;
    my $asBaksetExts= shift;
    my $bPretend= shift;

    my $mountable= $self->mountable();

    # mount all target mount objects
    my @sMountMessage= ();
    my $iMountResult= $mountable->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        logger->error("There was at least one fatal mount error on target. Backup set skipped.");
        logger->error(@sMountMessage);
        return -3;
    }
    logger->log(@sMountMessage);

    # check target dir
    unless ($self->isDir()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->get_value("path")."\" is not a directory. Backup set skipped.");
        return -1;
    }
    unless ($self->isWritable()) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$self->get_value("path")."\" is not writable. Backup set skipped.");
        return -2;
    }

    my $sBaksetExt= $asBaksetExts->[0];
    my $sBaksetMonth= strftime("%Y-%m", localtime);
    $self->{BAKSET_DATA} = {
        BAKSETEXT => $sBaksetExt,
        BAKSETEXTS => $asBaksetExts,
        BAKSETDIR => "$sBaksetMonth$sBaksetExt",
        BAKSETMONTH => $sBaksetMonth,
        BAKSETDAY => strftime("%Y-%m-%d", localtime),
        BAKDIRS => $self->getAllBakdirs(),
    };

    $self->mkdir($self->getBaksetDir()) unless $bPretend;
    return 0;
}

sub finishBackup {
    my $self= shift;

    my $aDf = $self->checkDf();
    if (defined $aDf) {
        logger->warn(join " ", @$aDf);
        logger->mailWarning("disc space too low", @$aDf);
    }

    $self->closeLogging();
    
    $self->cleanupTempfiles();

    my $mountable= $self->mountable();

    # unmount all target mounts
    $mountable->unmountAll();

    $self->{BAKSET_DATA}= undef;
    return 0;
}

sub prepareSourceBackup {
    my $self= shift;
    my $oSourcePeer= shift;
    my $bPretend= shift;

    my $asSourceExts= RabakLib::Set->GetAllPathExtensions($oSourcePeer);
    my $sBakDay= $self->getBaksetDay();

    my $hDirs= $self->getBakDirs();

    my @sBakDirs= $self->getBakdirsByExts(
        $self->getBaksetExts(),
        $asSourceExts,
        $hDirs,
    );

    my $sSubSet= '';
    my $aLastBakDir= $sBakDirs[0];
    if (scalar @sBakDirs && $hDirs->{$aLastBakDir}{date} eq $sBakDay) {
        $sSubSet= $hDirs->{$aLastBakDir}{subset};

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
    my $sSourceSet= "$sBakDay$sSubSet";
    my $sSourceSubdir= "$sSourceSet$sSourceExt";
    my $sBakDir= $self->getBaksetDir() . "/$sSourceSubdir";
    $self->{SOURCE_DATA}= {
        OLD_BAKDIRS => \@sBakDirs,
        SOURCEEXT => $sSourceExt,
        SUBSET => $sSubSet,
        SOURCESUBDIR => $sSourceSubdir,
        SOURCESET => $sSourceSet,
        SOURCEKEEP => $oSourcePeer->get_value("keep"),
        SOURCEINVENTORY => $oSourcePeer->get_value("inode_inventory"),
        BAKDIR => $sBakDir,
    };
    
    logger->info("Backup \"$sBakDay$sSourceExt\" exists, using subset \"$sSourceSubdir\".") if $sSubSet;

    $self->mkdir($sBakDir) unless $bPretend;
}

sub finishSourceBackup {
    my $self= shift;
    my $iBackupResult= shift;
    my $bPretend= shift;
    
    unless ($bPretend) {
        unless ($iBackupResult) {
            $self->inodeInventory();
            # remove old dirs if backup was successfully done
            $self->remove_old();
        }

        my $sSourceExt= $self->getSourceExt();
        $sSourceExt=~ s/^\./\-/;
        my $sCurrentLink= "current" . $self->getBaksetExt() . $sSourceExt;
        $self->unlink($sCurrentLink);
        $self->symlink($self->getBakDir(), $sCurrentLink);
    }
    $self->{SOURCE_DATA}= undef;
}

sub initLogging {
    my $self= shift;
    my $bPretend= shift;

    my $sBaksetDay= $self->getBaksetDay();
    my $sBaksetMonth= $self->getBaksetMonth();
    my $sBaksetDir= $self->getBaksetDir();
    my $sBaksetExt= $self->getBaksetExt();

    my $sLogDir= "$sBaksetMonth-log";
    my $sLogFile= "$sLogDir/$sBaksetDay$sBaksetExt.log";
    my $sLogFilePath= $self->getPath($sLogFile);

    unless ($bPretend) {
        $self->mkdir($sLogDir);
        my $sLogLink= "$sBaksetDir/$sBaksetDay$sBaksetExt.log";


        my $sError= logger->open($sLogFilePath, $self);
        if ($sError) {
            logger->warn("Can't open log file \"$sLogFilePath\" ($sError). Going on without...");
        }
        else {
            $self->symlink("../$sLogFile", "$sLogLink");
            my $sCurrentLogFileName= "current-log$sBaksetExt";
            $self->unlink($sCurrentLogFileName);
            $self->symlink($sLogFile, $sCurrentLogFileName);
        }
    }
    logger->info("Logging to: $sLogFilePath");
    logger->info("", "**** Only pretending, no changes are made! ****", "") if $bPretend;
}

sub closeLogging {
    my $self= shift;

    logger->close();
}

sub sort_show_key_order {
    my $self= shift;

    (
        $self->SUPER::sort_show_key_order(),
        $self->mountable()->sort_show_key_order(),
        "group", "mount",
    );
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

sub getAllBakdirs {
    my $self= shift;

    # get recursive file listing for 1 extra level
    my %hDirs= $self->getDirRecursive(undef, 1);

    my %hResult= ();

    # hDirs is of the format: { dir => { file => 1 }, file, ... }
    # The next three lines iterates over the values of the outer hash, skips the files, takes the dirs.
    # These dirs are iteratet over and all keys (=files) are collected. voila!
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
    my $hDirs= shift || $self->getAllBakdirs();

    my %hSetExts;
    my %hSourceExts;

    my $i= 1;
    map { $hSetExts{$_}= $i++ } @$asSetExts;
    map { $hSourceExts{$_}= $i++ } @$asSourceExts;

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