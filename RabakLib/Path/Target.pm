#!/usr/bin/perl

package RabakLib::Path::Target;

use warnings;
use strict;

use RabakLib::Log;

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub isPossibleValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    # if device is target, check if its already mounted.
    # if mounted, check if it's our target (and unmount if it is)
    unless ($sMountDevice) {
        push @$sCurrentMountMessage, logger->warn("Target devices have to be specified with device name");
        return 0;
    }
    my %checkResult = %{$self->_mount_check($sMountDevice)};
    push @$sCurrentMountMessage, logger->info($checkResult{INFO}) if $checkResult{INFO};
    push @$sCurrentMountMessage, logger->error($checkResult{ERROR}) if $checkResult{ERROR};
    # device is mounted but not target
    if ($checkResult{CODE} == 1) {
        return 0;
    }
    # device was mounted AND target
    if ($checkResult{CODE} == 2) {
        my $umountResult= $self->umount("$sMountDevice 2>&1");
        push @$sCurrentMountMessage, logger->warn("Device $sMountDevice was already mounted");
        push @$sCurrentMountMessage, logger->warn("Umount result: \"$umountResult\"") if $umountResult;
    }
    # ($checkResult{CODE} == 0: device not mounted)
    return 1;
}

sub isValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    my %checkResult = %{ $self->_mount_check($sMountDevice) };
    push @$sCurrentMountMessage, logger->info($checkResult{INFO}) if $checkResult{INFO};
    push @$sCurrentMountMessage, logger->error($checkResult{ERROR}) if $checkResult{ERROR};
    if ($checkResult{CODE} == 0) { # device is not mounted
        push @$sCurrentMountMessage, logger->warn("Device \"$sMountDevice\" is not mounted!");
    }
    elsif ($checkResult{CODE} == 1) { # device is no valid target
        $self->umount("\"$sMountDevice\"");
        if ($?) { # umount failed
            my $sMountResult= $self->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @$sCurrentMountMessage, logger->warn("Unmounting \"$sMountDevice\" failed with: $sMountResult!");
        }
        else {
            push @$sCurrentMountMessage, logger->info("Unmounted \"$sMountDevice\"");
        }
    }
    elsif ($checkResult{CODE} == 2) { # device mounted and valid target
        return 1;
    }
    return 0;
}

sub mountErrorIsFatal {
    my $self= shift;
    my $iMountResult= shift;
    
    return $iMountResult;
}

# tests if device is mounted and is a valid rabak target
# @param $sMountDevice
#   device to check
# @param $bUnmount
#   unmount the device if its a valid rabak media
# @return
#   hashtable:
#       {CODE} (int):
#           -1: no device specified
#            0: device is not mounted
#            1: device is mounted but no target media
#            2: device is/was mounted and is target media
#       {INFO} (string):
#            explaining information about CODE
#       {ERROR} (string):
#            additional error messages
#       {UMOUNT} (string):
#            result string of umount command (if executed)
sub _mount_check {
    my $self= shift;
    my $sMountDevice= shift;
    
    my $result= $self->SUPER::_mount_check($sMountDevice);

    my $sTargetValue= $self->get_value("group");
    my $sqTargetValue= quotemeta $sTargetValue;
    if ($self->get_switch('targetvalue')) {
        $sTargetValue.= "." . $self->get_switch('targetvalue');
        $sqTargetValue= quotemeta $sTargetValue;
    }
    else {
        $sqTargetValue.= '(\.\w+)?';
    }

    # if device is mounted
    if ($result->{CODE} == 1) {
        my $sMountDir= $result->{PATH};

        my $sDevConfFile= File::Spec->join($sMountDir, $self->get_switch('dev_conf_file', "rabak.dev.cf"));
        if ($self->isReadable("$sDevConfFile")) {
            if ($sTargetValue) {
                my $oDevConfFile= RabakLib::ConfFile->new($self->getLocalFile($sDevConfFile));
                my $oDevConf= $oDevConfFile->conf();
                my $sFoundTargets = $oDevConf->get_value('targetvalues') || '';
                if (" $sFoundTargets " =~ /\s$sqTargetValue\s/) {
                    $result->{CODE}= 2;
                    $result->{INFO}= "Target value \"$sTargetValue\" found on device \"$sMountDevice\"";
                }
                else {
                    $result->{INFO}= "Target value \"$sTargetValue\" not found on device \"$sMountDevice\" (found: \"" .
                        join("\", \"", split(/\s+/, $sFoundTargets)) .
                        "\")";
                }
            }
            else { # no target group specified -> if conf file is present, this is our target
                $result->{CODE}= 2;
                $result->{INFO}= "No target group specified";
            }
        }
        else {
            $result->{INFO}= "Device config file \"".$self->getFullPath($sDevConfFile)."\" not found on device \"$sMountDevice\"";
        }

    }
    return $result;
}

sub remove_old {
    my $self= shift;
    my $iKeep= shift;
    my @sBakDir= @_;
    
    return unless $iKeep;

    logger->info("Keeping last $iKeep versions");
    splice @sBakDir, 0, $iKeep;
    foreach (@sBakDir) {
        logger->info("Removing \"$_\"");
        $self->rmtree($_);
        logger->error($self->get_last_error()) if $self->get_last_exit;
    }
}

1;
