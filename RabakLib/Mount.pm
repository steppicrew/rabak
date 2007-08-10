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
    my $spMountDevice= ""; # set later
    my $spMountDir=    $sMountDir    ? " \"$sMountDir\""     : "";
    my $spMountType =  $sMountType   ? " -t \"$sMountType\"" : "";
    my $spMountOpts =  $sMountOpts   ? " -o\"$sMountOpts\""  : "";

    my %checkResult;

    my @sMountDevices= ();

    for my $sMountDevice (split(/\s+/, $sMountDeviceList)) {
        push @sMountDevices, $oPath->glob($sMountDevice);
    }

    # if no device were given, try mounting by mount point
    push @sMountDevices, '' if $#sMountDevices < 0;

    my @sMountMessage = ();
    my $iResult= 0;
    for my $sMountDevice (@sMountDevices) {
        my @sCurrentMountMessage = ();
        $sUnmount= $sMountDevice ne '' ? $sMountDevice : $sMountDir;
        $self->{UNMOUNT}= $sUnmount;
        $spMountDevice= $sMountDevice ? " \"$sMountDevice\""  : "";
        push @sCurrentMountMessage, RabakLib::Log->logger->info("Trying to mount \"$sUnmount\"");

        goto nextDevice unless $self->{PATH_OBJECT}->isPossibleValid($self, \@sCurrentMountMessage);

        $oPath->mount("$spMountType$spMountDevice$spMountDir$spMountOpts");
        if ($?) { # mount failed
            my $sMountResult= $oPath->get_error;
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @sCurrentMountMessage, RabakLib::Log->logger->warn("Mounting$spMountDevice$spMountDir failed with: $sMountResult!");
            goto nextDevice;
        }

        $iResult= $self->{PATH_OBJECT}->isValid($self, \@sCurrentMountMessage);
nextDevice:
        push @sMountMessage, @sCurrentMountMessage;
        last if $iResult;
    }
    push @{ $arMessage }, @sMountMessage;

    if ($sUnmount) {
        $self->{IS_MOUNTED}= 1 if $iResult;
        # We want to unmount in reverse order:
        unshift @{ $arUnmount }, $self if $self->get_value("unmount");
    }

    push @{ $arMessage }, RabakLib::Log->logger->info("Mounted$spMountDevice$spMountDir") if $iResult;
    push @{ $arMessage }, RabakLib::Log->logger->error("All mounts failed") unless $iResult;
    return $iResult;
}

sub unmount {
    my $self= shift;
    
    return unless $self->{IS_MOUNTED};

    $self->{PATH_OBJECT}->umount("\"$self->{UNMOUNT}\"");
    if ($?) {
        my $sResult= $self->get_error;
        chomp $sResult;
        $sResult =~ s/\r?\n/ - /g;
    
        RabakLib::Log->logger->warn("Unmounting \"$_\" failed: $sResult!");
        next;
    }
    RabakLib::Log->logger->log("Unmounted \"$_\"");
}

1;
