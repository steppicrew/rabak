#!/usr/bin/perl

package RabakLib::Peer::Target;

use warnings;
use strict;

use RabakLib::Log;
use RabakLib::ConfFile;

use vars qw(@ISA);

@ISA = qw(RabakLib::Peer);

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{MOUNTABLE}= RabakLib::Mountable->new($self);
    
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
    my $iKeep= shift;
    my @sBakDir= @_;
    
    return unless $iKeep;

    logger->info("Keeping last $iKeep versions");
    my $sqPath= quotemeta $self->getPath();
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
        logger->info("Removing \"$sDir\"");
        $self->rmtree($sDir);
        logger->error($self->get_last_error()) if $self->get_last_exit();
    }
}

sub prepareBackup {
    my $self= shift;

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
    return 0;
}

sub finishBackup {
    my $self= shift;

    # unmount all target mounts
    $self->unmountAll();
    return 0;
}

sub sort_show_key_order {
    my $self= shift;
    ($self->SUPER::sort_show_key_order(), "group", "mount");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};

    my @sSuperResult= @{$self->SUPER::show($hConfShowCache)};
    return [] unless @sSuperResult;
    
    return [
        "",
        "#" . "=" x 79,
        "# Target \"" . $self->getShowName() . "\": " . $self->getFullPath(),
        "#" . "=" x 79,
        @sSuperResult
    ];
}

1;
