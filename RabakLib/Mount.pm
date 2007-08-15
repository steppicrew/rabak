#!/usr/bin/perl

package RabakLib::Mount;

use warnings;
use strict;

use Data::Dumper;

use vars qw(@ISA);

use RabakLib::Log;

@ISA = qw(RabakLib::Conf);

sub new {
    my $class= shift;
    my $sName= shift;
    my $oParentConf= shift;

    my $self= $class->SUPER::new($sName, $oParentConf);
    
    $self->{IS_MOUNTED} = 0;
    $self->{PATH_OBJECT} = undef;
    $self->{UNMOUNT} = undef;

    bless $self, $class;
}

sub is_mounted {
    my $self= shift;
    
    return $self->{IS_MOUNTED};
}

# -----------------------------------------------------------------------------
#  Mount & Unmount
# -----------------------------------------------------------------------------

sub MountDir2Device {
    my $self= shift;
    my $sMountDir= shift;
    my $oPath= shift || RabakLib::Path->new(undef, undef);
    
    return undef unless defined $sMountDir;
    
    my $sFsTab= $oPath->cat("/etc/fstab") || '';
    my $sqMountDir= quotemeta $sMountDir;
    return $1 if $sFsTab=~ /^(\S+)\s+$sqMountDir\s+/m;
    return undef; 
    
}

sub MountDevice2Dir {
    my $self= shift;
    my $sMountDevice= shift;
    my $oPath= shift || RabakLib::Path->new(undef, undef);
    
    return undef unless defined $sMountDevice;
    
    my $sFsTab= $oPath->cat("/etc/fstab") || '';
    my $sqMountDevice= quotemeta $sMountDevice;
    return $1 if $sFsTab=~ /^$sqMountDevice\s+(\S+)\s+/m;
    return undef; 
    
}

# @param $oPath
#       A RakakPath for system commands
# @param $arMessage
#       A ref to an array, in which _mount stores warnings and messages
# @param $arUnmount
#       A ref to an array, in which _mount stores the mount points that need unmounting
# return
#       0: failed
#       1: succeeded
sub mount {
    my $self= shift;
    my $oPath= shift;
    my $arMessage= shift || [];
    my $arUnmount= shift || [];
    
    $self->{PATH_OBJECT}= $oPath;

    my $sMountDeviceList= $self->get_value("device") || '';
    my $sMountDir= $self->get_value("directory") || '';
    my $sMountType= $self->get_value("type") || '';
    my $sMountOpts= $self->get_value("opts") || '';
    my $sUnmount= "";

    # parameters for mount command
    my $spMountOpts= "";
    $spMountOpts.=  "-t \"$sMountType\" " if $sMountType;
    $spMountOpts.=  "-o\"$sMountOpts\" " if $sMountOpts;

    my %checkResult;

    my @sMountDevices= ();

    for my $sMountDevice (split(/\s+/, $sMountDeviceList)) {
        push @sMountDevices, $oPath->glob($sMountDevice);
    }

    # if no device were given, try mounting by mount point
    push @sMountDevices, $self->MountDir2Device($sMountDir, $oPath) if $#sMountDevices < 0;

    # array for collected mount messages (will be reseted if mount succeeds)
    my @sMountMessage = ();
    # array for mount messages of current try
    my @sCurMountMessage= ();
    my $iResult= 0;
    for my $sMountDevice (@sMountDevices) {
        @sCurMountMessage= ();
        $sMountDir= $self->MountDevice2Dir($sMountDevice, $oPath) unless $sMountDir;
        unless ($sMountDir && $sMountDevice) {
            push @$arMessage, RabakLib::Log->logger->error("Could not find mount point for device \"$sMountDevice\"") unless $sMountDir;
            push @$arMessage, RabakLib::Log->logger->error("Could not find device for mount point \"$sMountDir\"") unless $sMountDevice;
            next;
        }
        # set umount parameter to mount point if possible
        push @$arMessage, RabakLib::Log->logger->info("Trying to mount \"$sMountDevice\" to \"$sMountDir\"");

        # check if device is already mounted
        my $sMountPath= $oPath->checkMount($sMountDevice, \@sCurMountMessage);

        # don't know which device to check: skip this mount (this should not happen!)
        if ($sMountPath eq "0") {
            push @$arMessage, RabakLib::Log->logger->error("Don't know which device to check");
            next;
        }

        # device is mounted but not valid: check next device
        next if $sMountPath eq "2";

        # device is mounted on $sMountPath (and valid): stop checking, this is our device
        if ($sMountPath eq $sMountDir) {
            push @$arMessage, RabakLib::Log->logger->info("\"$sMountDevice\" is already mounted on \"$sMountDir\"");
            $iResult= 1;
            last;
        }

        # 1: device is not mounted
        # if mounted, unmount
        unless ($sMountPath eq "1") {
            push @$arMessage, RabakLib::Log->logger->warn("\"$sMountDevice\" is already mounted on \"$sMountPath\"");
            next unless $self->unmount($sMountPath, "force");
        }

        # ...and mount
        $oPath->mount("$spMountOpts\"$sMountDevice\" \"$sMountDir\"");
        if ($?) { # mount failed
            my $sMountResult= $oPath->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @$arMessage, RabakLib::Log->logger->warn("Mounting \"$sMountDevice\" on \"$sMountDir\" failed with: $sMountResult!");
            next;
        }

        # check mount result again
        $sMountPath= $oPath->checkMount($sMountDevice, \@sCurMountMessage);

        # device is not mounted: try next
        if ($sMountPath eq "1") {
            push @$arMessage, RabakLib::Log->logger->error("\"$sMountDevice\" not mounted");
            next;
        }

        # device is mounted at the correct path: quit here
        if ($sMountPath eq $sMountDir) {
            push @$arMessage, RabakLib::Log->logger->info("Mounted \"$sMountDevice\" on \"$sMountDir\"");
            $iResult= 1;
            last;
        }

        # device is mounted but not valid(2) or mounted at wrong path: unmount again and try next
        if ($sMountPath eq "2") {
            $self->unmount($sMountDevice, "force");
        }
        else {
            push @$arMessage, RabakLib::Log->logger->error("\"$sMountDevice\" is  mounted on \"$sMountPath\" instead of \"$sMountDir\"");
            $self->unmount($sMountPath, "force");
        }
    }
    continue {
        # collect all previous log messages 
        push @sMountMessage, @sCurMountMessage;
    }
    if ($iResult) {
        push @$arMessage, @sCurMountMessage;
    }
    else {
        push @$arMessage, @sMountMessage;
    }

    if ($sMountDir) {
        $self->{UNMOUNT}= $sMountDir;
        $self->{IS_MOUNTED}= 1 if $iResult;
        # We want to unmount in reverse order:
        unshift @{ $arUnmount }, $self if $self->get_value("unmount", 1);
    }

    push @$arMessage, RabakLib::Log->logger->error("All mounts failed") unless $iResult;
    return $iResult;
}

sub unmount {
    my $self= shift;
    my $sMountDir= shift || $self->{UNMOUNT};
    my $bForce= shift;
    
    return unless $sMountDir && ($bForce || $self->{IS_MOUNTED});

    $self->{PATH_OBJECT}->umount("\"$sMountDir\"");
    if ($?) {
        my $sResult= $self->{PATH_OBJECT}->get_error;
        chomp $sResult;
        $sResult =~ s/\r?\n/ - /g;
        RabakLib::Log->logger->warn("Unmounting \"$sMountDir\" failed: $sResult!");
        RabakLib::Log->logger->info("Trying lazy unmount.");

        $self->{PATH_OBJECT}->umount("-l \"$sMountDir\"");
        if ($?) {
            my $sResult= $self->{PATH_OBJECT}->get_error;
            chomp $sResult;
            $sResult =~ s/\r?\n/ - /g;
    
            RabakLib::Log->logger->error("Even lazy unmounting \"$sMountDir\" failed: $sResult!");
            return 0;
        }
    }
    RabakLib::Log->logger->log("Successfully unmounted \"$sMountDir\"");
    return 1;
}

sub sort_show_key_order {
    my $self= shift;
    ("device", "directory", "unmount", $self->SUPER::sort_show_key_order());
}

1;
