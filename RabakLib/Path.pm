#!/usr/bin/perl

package RabakLib::Path;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use Data::Dumper;
use File::Spec ();
use File::Temp ();

# use RabakLib::Log;

use RabakLib::Mount;

use vars qw(@ISA);

@ISA = qw(RabakLib::PathBase);

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
    my $oMount= shift;
    
    my $sMountDevice= $oMount->get_value("device");

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

sub mountErrorIsFatal {
    my $self= shift;
    my $iMountResult= shift;
    
    return 0;
}
sub getMountObjects {
    my $self= shift;

    return () unless $self->get_property("mount");

    my @oConfs= $self->resolveObjects("mount");
    my @oMounts= ();
    for my $oConf (@oConfs) {
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' mounts: should this set parent for inheriting values?
            $oConf= RabakLib::Conf->new(undef, $self);
            $oConf->set_value("directory", $sPath);
        }
        push @oMounts, RabakLib::Mount->CloneConf($oConf);
    } 
    return @oMounts;
}

# return
#       0: failed
#       1: succeeded
sub mountAll {
    my $self= shift;
    my $arMessage= shift || [];

    my @aMounts= $self->getMountObjects();
    
    # Collect all mount errors, we want to output them later
    my $iResult= 1; # defaults to mount succeeded
    
    my $arAllMounts= [];

    for my $oMount (@aMounts) {
        $iResult = $oMount->mount($self, $arMessage, $arAllMounts);
        # quit if mount failed
        # TODO: is this right for source objects?
        last if $self->mountErrorIsFatal($iResult);
    }
    $self->{_MOUNT_LIST}= $arAllMounts;

    return $iResult;
}

sub get_mounts {
    my $self= shift;

    return $self->{_MOUNT_LIST} || [];
}

sub unmountAll {
    my $self= shift;
    
    return unless $self->{_MOUNT_LIST};

    my @sUnmount= @{ $self->{_MOUNT_LIST} };

    for my $oMount (@sUnmount) {
        $oMount->umount();
    }

    $self->{_MOUNT_LIST}= []
}

1;
