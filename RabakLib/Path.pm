#!/usr/bin/perl

package RabakLib::Path;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use Data::Dumper;
use File::Spec ();
use File::Temp ();

use vars qw(@ISA);

@ISA = qw(RabakLib::PathBase);

# possible parameters for new:
#   (RabakLib::Set, $sConfName)
#   (%Values)
sub new {
    my $class= shift;
    
    my $oSet= undef;
    my %Values=();
    # if first parameter is a reference, a bakset object was specified 
    if (scalar @_ && ref $_[0]) {
        $oSet= shift;
        my $sConfName= shift;

        if ($oSet && $sConfName) {
            my $oPath= $oSet->get_global_node($sConfName);
            die "FATAL ERROR: Could not resolve '$sConfName'" unless $oPath || $sConfName !~ /^\&/;

            my $sPath;
            unless ($oPath) {
                $sPath= $oSet->get_global_value($sConfName);
                $oPath= $oSet->get_global_node($sPath) if $sPath;
            }
            $sPath= $sConfName unless $sPath;
            %Values= $oPath ? %{$oPath->{VALUES}} : ( path => $sPath );
        }
        die "FATAL ERROR: Setting 'mount' in bakset is deprecated! Please set mount in Source and/or Target Objects" if $oSet->get_value("mount");
    }
    else {
        %Values= (@_);
    }
    my $self= $class->SUPER::new(%Values);
    $self->{ERRORCODE} = 0;
    $self->{DEBUG} = 0;

    if ($oSet) {
        $self->{SET}= $oSet;
    }

    bless $self, $class;
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    if ($self->is_remote()) {
        $sPath = $self->get_value("host") . ":$sPath";
        $sPath = $self->get_value("user") . "\@$sPath" if $self->get_value("user");
    }
    return $sPath;
}

# get path works only with file object!
# should be overwritten by other subclasses
sub getPath {
    my $self= shift;
    my $sPath= shift || '.';

    return $sPath unless $self->get_value("path");

    $self->set_value("path", $self->abs_path($self->get_value("path"))) unless File::Spec->file_name_is_absolute($self->get_value("path"));

    $sPath= File::Spec->canonpath($sPath); # simplify path
    $sPath= File::Spec->rel2abs($sPath, $self->get_value("path")) unless File::Spec->file_name_is_absolute($sPath);
    return $sPath;
}

# -----------------------------------------------------------------------------
#  Mount & Unmount
# -----------------------------------------------------------------------------

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
#            1: device is mounted
#       {INFO} (string):
#            explaining information about CODE
#       {ERROR} (string):
#            additional error messages
#       {UMOUNT} (string):
#            result string of umount command (if executed)
#       {PATH} (string):
#            path where device is mounted (if executed)
sub _mount_check {
    my $self= shift;
    my $sMountDevice= shift || '';
    my $sTargetValue= shift || '';
    my $bUnmount= shift || 0;

    return { CODE => -1 } if !$sMountDevice;

    $sMountDevice= $self->abs_path($sMountDevice);

    my $sqMountDevice= quotemeta $sMountDevice;

    my $cur_mounts= $self->mount;
    # TODO:
    #     check for "mount" outputs different from '/dev/XXX on /mount/dir type ...' on other systems
    #     notice: the check for "type" after mount dir is because of missing delimiters if mount dir contains spaces!
    if ($cur_mounts =~ /^$sqMountDevice\son\s+(\/.*)\stype\s/m) {
        return {
            PATH => $1,
            CODE => 1,
        }
    }
    return {
        CODE => 0,
    };
}

sub isPossibleValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    return 1;
}

sub isValid {
    my $self= shift;
    my $sMountDevice= shift;
    my $sCurrentMountMessage= shift;

    return 1;
}

sub mountWasFatal {
    my $self= shift;
    my $iMountResult= shift;
    
    return 0;
}

# @param $oMount
#       A RakakConf object containing the mount point information
# @param $arMessage
#       A ref to an array, in which _mount stores warnings and messages
# @param $arUnmount
#       A ref to an array, in which _mount stores the mount points that need unmounting
# @param $arAllMount
#       A ref to an array, in which _mount stores all mount points
# return
#       0: failed
#       1: succeeded
sub _mount {
    my $self= shift;
    my $oMount= shift;
    my $arMessage = shift || {};
    my $arUnmount= shift || {};
    my $arAllMount= shift || {};

    my $sMountDeviceList= $oMount->get_value("device") || '';
    my $sMountDir= $oMount->get_value("directory") || '';
    my $sTargetGroup= $self->get_value("group");
    my $sMountType= $oMount->get_value("type") || '';
    my $sMountOpts= $oMount->get_value("opts") || '';
    my $sUnmount= "";

    # parameters for mount command
    my $spMountDevice= ""; # set later
    my $spMountDir=    $sMountDir    ? " \"$sMountDir\""     : "";
    my $spMountType =  $sMountType   ? " -t \"$sMountType\"" : "";
    my $spMountOpts =  $sMountOpts   ? " -o\"$sMountOpts\""  : "";

    my %checkResult;

    my @sMountDevices= ();

    for my $sMountDevice (split(/\s+/, $sMountDeviceList)) {
        push @sMountDevices, $self->glob($sMountDevice);
    }

    # if no device were given, try mounting by mount point
    push @sMountDevices, '' if $#sMountDevices < 0;

    my @sMountMessage = ();
    my $iResult= 0;
    for my $sMountDevice (@sMountDevices) {
        my @sCurrentMountMessage = ();
        $sUnmount= $sMountDevice ne '' ? $sMountDevice : $sMountDir;
        $spMountDevice= $sMountDevice ? " \"$sMountDevice\""  : "";
        push @sCurrentMountMessage, logger->info("Trying to mount \"$sUnmount\"");

        goto nextDevice unless $self->isPossibleValid($sMountDevice, \@sCurrentMountMessage);

        $self->mount("$spMountType$spMountDevice$spMountDir$spMountOpts");
        if ($?) { # mount failed
            my $sMountResult= $self->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @sCurrentMountMessage, logger->warn("Mounting$spMountDevice$spMountDir failed with: $sMountResult!");
            goto nextDevice;
        }

        $iResult= $self->isValid($sMountDevice, \@sCurrentMountMessage);
nextDevice:
        push @sMountMessage, @sCurrentMountMessage;
        last if $iResult;
    }
    push @{ $arMessage }, @sMountMessage;

    if ($sUnmount) {
        push @{ $arAllMount }, $sUnmount;

        # We want to unmount in reverse order:
        unshift @{ $arUnmount }, $sUnmount if $oMount->get_value("unmount") && $iResult;
    }

    push @{ $arMessage }, logger->info("Mounted$spMountDevice$spMountDir") if $iResult;
    push @{ $arMessage }, logger->error("All mounts failed") unless $iResult;
    return $iResult;
}

sub getMountObjects {
    my $self= shift;

    my $sMount= $self->get_value("mount");
    my @aMounts;
    unless ($sMount) {
        my $oMount= $self->get_node("mount");
        push @aMounts, $oMount if $oMount;
    }
    else {
        for my $sMountName (split /\s+/, $sMount) {
            my $oMount= $self->get_global_set_node($sMountName);
            push @aMounts, $oMount if $oMount;
        }
    }
    return @aMounts;
}

# return
#       0: failed
#       1: succeeded
sub mountAll {
    my $self= shift;
    my $arMessage= shift || [];

    my @aMounts= $self->getMountObjects();
    
    # Collect all mount errors, we want to output them later
    my $arUnmount= $self->{_UNMOUNT_LIST} || [];
    my $arAllMount= $self->{_ALL_MOUNT_LIST} || [];

    my $iResult= 1; # defaults to mount succeeded

    for my $sMount (@aMounts) {
        $iResult = $self->_mount($sMount, $arMessage, $arUnmount, $arAllMount);
        # quit if mount failed
        # TODO: is this right for source objects?
        last if $self->mountWasFatal($iResult);
    }

    $self->{_UNMOUNT_LIST}= $arUnmount;
    $self->{_ALL_MOUNT_LIST}= $arAllMount;

    return $iResult;
}

sub get_mounts {
    my $self= shift;

    return $self->{_UNMOUNT_LIST} || [];
}

sub unmountAll {
    my $self= shift;
    
    return unless $self->{_UNMOUNT_LIST};

    my @sAllMount= @{ $self->{_ALL_MOUNT_LIST} };
    my @sUnmount= @{ $self->{_UNMOUNT_LIST} };

    my %sAllMount;
    map { $sAllMount{$_}= 1; } @sAllMount;

    for (@sUnmount) {
        $self->umount("\"$_\"");
        if ($?) {
            my $sResult= $self->get_error;
            chomp $sResult;
            $sResult =~ s/\r?\n/ - /g;
            next unless $sAllMount{$_};

            logger->warn("Unmounting \"$_\" failed: $sResult!");
            next;
        }
        $self->log("Unmounted \"$_\"");
    }

    $self->{_UNMOUNT_LIST}= []
}

1;
