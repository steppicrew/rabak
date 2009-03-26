#!/usr/bin/perl

package Rabak::Mount;

use warnings;
use strict;
no warnings 'redefine';

use Data::Dumper;

use vars qw(@ISA);

use Rabak::Conf;
use Rabak::Log;

@ISA = qw(Rabak::Conf);

sub new {
    my $class= shift;
    my $sName= shift;
    my $oParentConf= shift;

    my $self= $class->SUPER::new($sName, $oParentConf);
    
    $self->{PEER_OBJECT} = undef;
    $self->{MOUNTPOINT} = undef;

    bless $self, $class;
}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return ('device', 'directory', 'type', 'options', 'unmount', 'lazy_unmount', shift->SUPER::PropertyNames());
}

sub is_mounted {
    my $self= shift;
    
    return $self->{MOUNTPOINT};
}

# -----------------------------------------------------------------------------
#  Mount & Unmount
# -----------------------------------------------------------------------------

sub MountDir2Device {
    my $self= shift;
    my $sMountDir= shift;
    my $oPeer= shift || Rabak::Peer::Mountable->new(undef, undef);
    
    return undef unless defined $sMountDir;
    
    my $sFsTab= $oPeer->cat("/etc/fstab") || '';
    my $sqMountDir= quotemeta $sMountDir;
    return $oPeer->abs_path($1) if $sFsTab=~ /^(\S+)\s+$sqMountDir\s+/m;
    return undef; 
    
}

sub MountDevice2Dir {
    my $self= shift;
    my $sMountDevice= shift;
    my $oPeer= shift || Rabak::Peer::Mountable->new(undef, undef);
    
    return undef unless defined $sMountDevice;
    
    my $sFsTab= $oPeer->cat("/etc/fstab") || '';
    my $sqMountDevice= quotemeta $sMountDevice;
    return $oPeer->abs_path($1) if $sFsTab=~ /^$sqMountDevice\s+(\S+)\s+/m;
    return undef; 
    
}

# @param $oPeer
#       A RakakPeer for system commands
# @param $arMessage
#       A ref to an array, in which _mount stores warnings and messages
# @param $arUnmount
#       A ref to an array, in which _mount stores the mount points that need unmounting
# return
#       0: failed
#       1: succeeded
sub mount {
    my $self= shift;
    my $oPeer= shift;
    my $arMessage= shift || [];
    my $arUnmount= shift || [];
    
    $self->{PEER_OBJECT}= $oPeer;

    my @aMountDeviceList= $self->resolveObjects("device");
    my $sMountDir= $self->get_value("directory") || '';
    my $sMountType= $self->get_value("type") || '';
    my $sMountOpts= $self->get_value("options") || $self->get_value("opts") || '';
    my $sUnmount= "";

    # parameters for mount command
    my @spMountOpts= ();
    push @spMountOpts, '-t', $sMountType if $sMountType;
    push @spMountOpts, '-o', $sMountOpts if $sMountOpts;

    my %checkResult;

    my @sMountDevices= ();

    for my $sMountDevice (@aMountDeviceList) {
        push @sMountDevices, $oPeer->glob($sMountDevice);
    }

    # if no device were given, try mounting by mount point
    push @sMountDevices, $self->MountDir2Device($sMountDir, $oPeer) unless scalar @sMountDevices;

    # array for collected mount messages (will be reseted if mount succeeds)
    my @sMountMessage = ();
    # array for mount messages of current try
    my @sCurMountMessage= ();
    my $iResult= 0;
    for my $sMountDevice (@sMountDevices) {
        @sCurMountMessage= ();
        $sMountDir= $self->MountDevice2Dir($sMountDevice, $oPeer) unless $sMountDir;
        unless ($sMountDir && $sMountDevice) {
            push @$arMessage, Rabak::Log->logger->error("Could not find mount point for device \"$sMountDevice\"") unless $sMountDir;
            push @$arMessage, Rabak::Log->logger->error("Could not find device for mount point \"$sMountDir\"") unless $sMountDevice;
            next;
        }
        # set umount parameter to mount point if possible
        push @$arMessage, Rabak::Log->logger->info("Trying to mount \"$sMountDevice\" to \"$sMountDir\"");

        # check if device is already mounted
        my $sMountPath= $oPeer->checkMount($sMountDevice, \@sCurMountMessage);

        # don't know which device to check: skip this mount (this should not happen!)
        if ($sMountPath eq "0") {
            push @$arMessage, Rabak::Log->logger->error("Don't know which device to check");
            next;
        }

        # device is mounted but not valid: check next device
        next if $sMountPath eq "2";

        # device is mounted on $sMountPath (and valid): stop checking, this is our device
        if ($sMountPath eq $sMountDir) {
            push @$arMessage, Rabak::Log->logger->info("\"$sMountDevice\" is already mounted on \"$sMountDir\"");
            @sMountMessage= @sCurMountMessage;
            $iResult= 1;
            last;
        }

        # 1: device is not mounted
        # if mounted, unmount
        unless ($sMountPath eq "1") {
            push @$arMessage, Rabak::Log->logger->warn("\"$sMountDevice\" is already mounted on \"$sMountPath\"");
            next unless $self->unmount($sMountPath, $arMessage);
        }

        # ...and mount
        $oPeer->mount(scalar $oPeer->shell_quote(@spMountOpts, $sMountDevice, $sMountDir));
        if ($?) { # mount failed
            my $sMountResult= $oPeer->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @$arMessage, Rabak::Log->logger->warn("Mounting \"$sMountDevice\" on \"$sMountDir\" failed with: $sMountResult!");
            next;
        }

        # check mount result again
        $sMountPath= $oPeer->checkMount($sMountDevice, \@sCurMountMessage);

        # device is not mounted: try next
        if ($sMountPath eq "1") {
            push @$arMessage, Rabak::Log->logger->error("\"$sMountDevice\" not mounted");
            next;
        }

        # device is mounted at the correct path: quit here
        if ($sMountPath eq $sMountDir) {
            push @$arMessage, Rabak::Log->logger->info("Mounted \"$sMountDevice\" on \"$sMountDir\"");
            @sMountMessage= @sCurMountMessage;
            $iResult= 1;
            last;
        }

        # device is mounted but not valid(2) or mounted at wrong path: unmount again and try next
        if ($sMountPath eq "2") {
            $self->unmount($sMountDevice, $arMessage);
        }
        else {
            push @$arMessage, Rabak::Log->logger->error("\"$sMountDevice\" is  mounted on \"$sMountPath\" instead of \"$sMountDir\"");
            $self->unmount($sMountPath, $arMessage);
        }
    }
    continue {
        # collect all previous log messages 
        push @sMountMessage, @sCurMountMessage;
    }
    push @$arMessage, @sMountMessage;

    if ($iResult && $sMountDir) {
        $self->{MOUNTPOINT}= $sMountDir;
        # We want to unmount in reverse order:
        unshift @{ $arUnmount }, $self if $self->get_value("unmount", 1);
    }

    push @$arMessage, Rabak::Log->logger->error("All mounts failed") unless $iResult;
    return $iResult;
}

sub unmount {
    my $self= shift;
    my $sMountDir= shift || $self->{MOUNTPOINT};
    my $arMessages= shift;
    
    my $bLogMessages= ! defined $arMessages;
    $arMessages= [] if $bLogMessages;
    
    return unless $sMountDir;

    my $oPeer = $self->{PEER_OBJECT};
    $oPeer->umount($oPeer->shell_quote($sMountDir));
    if ($?) {
        my $sResult= $oPeer->get_error;
        chomp $sResult;
        $sResult =~ s/\r?\n/ - /g;
        my $sError= "Unmounting \"$sMountDir\" failed: $sResult!";
        unless ($self->get_value("lazy_unmount")) {
            push @$arMessages, Rabak::Log->logger->error($sError);
            Rabak::Log->logger->log(@$arMessages) if $bLogMessages;
            return 0;
        }
        push @$arMessages, Rabak::Log->logger->warn($sError);
        push @$arMessages, Rabak::Log->logger->info("Trying lazy unmount.");

        $oPeer->umount("-l " . $oPeer->shell_quote($sMountDir));
        if ($?) {
            my $sResult= $oPeer->get_error;
            chomp $sResult;
            $sResult =~ s/\r?\n/ - /g;
    
            push @$arMessages, Rabak::Log->logger->error("Even lazy unmounting \"$sMountDir\" failed: $sResult!");
            Rabak::Log->logger->log(@$arMessages) if $bLogMessages;
            return 0;
        }
    }
    push @$arMessages, Rabak::Log->logger->info("Successfully unmounted \"$sMountDir\"");
    Rabak::Log->logger->log(@$arMessages) if $bLogMessages;
    $self->{MOUNTPOINT}= undef;
    return 1;
}

1;
