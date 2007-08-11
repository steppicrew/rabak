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

sub CloneConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::CloneConf($oOrigConf);

    my $sPath= $new->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+\:\/\/)?(\S+\@)?([\-0-9a-z\.]+)(\:\d+)?\://i) {
        $sPath= "$1$sPath" if $1;
        $new->set_value("path", $sPath);
        my $sUser= $2 || '';
        my $sHost= $3;
        my $iPort= $4 || 0;
        $sUser=~ s/\@$//;
        $iPort=~ s/^\://;
        $new->set_value("host", $sHost);
        $new->set_value("user", $sUser) if $sUser;
        $new->set_value("port", $iPort) if $iPort;
    }

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    return $new;
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    if ($self->is_remote()) {
        my $sUser= $self->get_value("user");
        my $sHost= $self->get_value("host");
        my $iPort= $self->get_value("port", 22);
        $sPath = "$iPort:$sPath" if $iPort != 22;
        $sPath = "$sHost:$sPath";
        $sPath = "$sUser\@$sPath" if $sUser;
    }
    return $sPath;
}

sub show {
    my $self= shift;
    
    $self->SUPER::show();
    
    my  @oMounts= $self->getMountObjects();
    for my $oMount (@oMounts) {
        print "\n";
        $oMount->show();
    }
    print "\n";
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
# @param $sMountDir
#   mount dir in fstab if $sMountDevice is not given
# @return
#   0 : don't know which device to check
#   1 : device is not mounted
#   2 : device is not valid (set by overwriting method)
#   <path>: path the device is mounted at
#   
sub checkMount {
    my $self= shift;
    my $sMountDevice= shift;
    my $sMountDir= shift;
    my $arMountMessages= shift;
    
    return 0 unless $sMountDevice || $sMountDir;

    unless ($sMountDevice) {
        my $sFsTab= $self->cat("/etc/fstab") || '';
        my $sqMountDir= quotemeta $sMountDir;
        $sMountDevice= $1 if $sFsTab=~ /^(\S+)\s+$sqMountDir\s+/m; 
    }

    return 0 unless $sMountDevice;

    $sMountDevice= $self->abs_path($sMountDevice);

    my $sqMountDevice= quotemeta $sMountDevice;

    my $cur_mounts= $self->mount;
    # TODO:
    #     check for "mount" outputs different from '/dev/XXX on /mount/dir type ...' on other systems
    #     notice: the check for "type" after mount dir is because of missing delimiters if mount dir contains spaces!
    return $1 if $cur_mounts =~ /^$sqMountDevice\son\s+(\/.*)\stype\s/m;
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
        $oMount->unmount();
    }
}

1;
