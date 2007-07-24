#!/usr/bin/perl

package RabakLib::TargetPath;

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub new {
    my $class = shift;
    my $oSet= shift;

    my $self= $class->SUPER::new($oSet, "target");
    bless $self, $class;

    unless ($self->get_value("group")) {
        my $sGroup= $self->get_set_value("targetgroup");
        if ($sGroup) {
            $self->set_value("group", $sGroup);
            $self->log($self->warnMsg("BakSet option \"targetgroup\" is deprecated. Please use \"group\" in Target Objects! (see Doc)"));
        }
    }
    unless ($self->get_value("discfree_threshold")) {
        my $sDFT= $self->get_set_value("target_discfree_threshold");
        if ($sDFT) {
            $self->set_value("discfree_threshold", $sDFT);
            $self->log($self->warnMsg("BakSet option \"target_discfree_threshold\" is deprecated. Please use \"discfree_threshold\" in Target Objects! (see Doc)"));
        }
    }
    return $self;
}

sub isPossibleValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    # if device is target, check if its already mounted.
    # if mounted, check if it's our target (and unmount if it is)
    unless ($sMountDevice) {
        push @$sCurrentMountMessage, $self->warnMsg("Target devices have to be specified with device name");
        return 0;
    }
    my %checkResult = %{$self->_mount_check($sMountDevice, 1)};
    push @$sCurrentMountMessage, $self->infoMsg($checkResult{INFO}) if $checkResult{INFO};
    push @$sCurrentMountMessage, $self->errMsg($checkResult{ERROR}) if $checkResult{ERROR};
    if ($checkResult{CODE} == 1) {
        return 0;
    }
    if ($checkResult{CODE} == 2) {
        push @$sCurrentMountMessage, $self->warnMsg("Device $sMountDevice was already mounted");
        push @$sCurrentMountMessage, $self->warnMsg("Umount result: \"${checkResult{UMOUNT}}\"") if $checkResult{UMOUNT};
    }
}

sub isValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    my %checkResult = %{ $self->_mount_check($sMountDevice, 0) };
    push @$sCurrentMountMessage, $self->infoMsg($checkResult{INFO}) if $checkResult{INFO};
    push @$sCurrentMountMessage, $self->errMsg($checkResult{ERROR}) if $checkResult{ERROR};
    if ($checkResult{CODE} == 0) { # device is not mounted
        push @$sCurrentMountMessage, $self->warnMsg("Device \"$sMountDevice\" is not mounted!");
    }
    elsif ($checkResult{CODE} == 1) { # device is no valid target
        $self->umount("\"$sMountDevice\"");
        if ($?) { # umount failed
            my $sMountResult= $self->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @$sCurrentMountMessage, $self->warnMsg("Unmounting \"$sMountDevice\" failed with: $sMountResult!");
        }
        else {
            push @$sCurrentMountMessage, $self->infoMsg("Unmounted \"$sMountDevice\"");
        }
    }
    elsif ($checkResult{CODE} == 2) { # device mounted and valid target
        return 1;
    }
    return 0;
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
    my $sMountDevice= shift || '';
    my $bUnmount= shift || 0;
    
    my $result= $self->SUPER::_mount_check($sMountDevice, $bUnmount);

    my $sTargetValue= $self->get_value("group");
    my $sqTargetValue= quotemeta $sTargetValue;
    if ($self->get_set_value('switch.targetvalue')) {
        $sTargetValue.= "." . $self->get_set_value('switch.targetvalue');
        $sqTargetValue= quotemeta $sTargetValue;
    }
    else {
        $sqTargetValue.= '(\.\w+)?';
    }

    # if device is mounted
    if ($result->{CODE} == 1) {
        my $sMountDir= $result->{PATH};

        my $sDevConfFile= File::Spec->join($sMountDir, $self->get_set_value('switch.dev_conf_file', "rabak.dev.cf"));
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

        $result->{UMOUNT}= $self->umount("$sMountDevice 2>&1") if ($result->{CODE} == 2) && $bUnmount;
    }
    return $result;
}

sub remove_old {
    my $self= shift;
    my $iKeep= shift;
    my @sBakDir= @_;
    
    return unless $iKeep;

    $self->log($self->infoMsg("Keeping last $iKeep versions"));
    splice @sBakDir, 0, $iKeep;
    unless ($self->get_set_value('switch.pretend')) {
        foreach (@sBakDir) {
            $self->log($self->infoMsg("Removing \"$_\""));
            $self->rmtree($_);
            $self->log($self->errorMsg($self->get_last_error)) if $self->get_last_exit;
        }
    }
}

1;
