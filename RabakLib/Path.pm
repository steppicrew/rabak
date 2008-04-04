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
    
    if ($sPath) {
        # remove leading "file://" etc.
        warn("Internel error: '$1' should already been removed. Please file a bug report with config included!") if $sPath=~ s/^(\w+\:\/\/)//;
        # extract hostname, user and port
        if ($sPath=~ s/^(\S+?\@)?([\-0-9a-z\.]+)(\:\d+)?\://i) {
            my $sUser= $1 || '';
            my $sHost= $2;
            my $iPort= $3 || 0;
            $sUser=~ s/\@$//;
            $iPort=~ s/^\://;
            $new->set_value("host", $sHost);
            $new->set_value("user", $sUser) if $sUser;
            $new->set_value("port", $iPort) if $iPort;
        }
        $new->set_value("path", $sPath);
    }

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    return $new;
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    return $self->getUserHostPort(":") . "$sPath"
}

sub getUserHost {
    my $self= shift;
    my $sSeparator= shift || '';

    return "" unless $self->is_remote();

    my $sUser= $self->get_value("user");
    return ($sUser ? "$sUser\@" : "") .
        $self->get_value("host") .
        $sSeparator;
}

sub getUserHostPort {
    my $self= shift;
    my $sSeparator= shift || '';

    return "" unless $self->is_remote();

    my $iPort= $self->get_value("port", 22);
    return $self->getUserHost() .
        ($iPort == 22 ? "" : ":$iPort") .
        $sSeparator;
}

sub sort_show_key_order {
    my $self= shift;
    ("host", "user", "path", $self->SUPER::sort_show_key_order());
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    my  @oMounts= $self->getMountObjects();
    $self->SUPER::show($hConfShowCache);
    
    print "\n# Referenced mounts:" if scalar @oMounts;

    for my $oMount (@oMounts) {
        print "\n";
        $oMount->show($hConfShowCache);
    }
    print "\n";
}

# get path works only with file object!
# should be overwritten by other subclasses
sub getPath {
    my $self= shift;
    my $sPath= shift || '.';
    
    my $sBasePath= $self->get_value("path");

    return $sPath unless $sBasePath;

    unless (File::Spec->file_name_is_absolute($sBasePath)) {
        $sBasePath= $self->abs_path($sBasePath);
        $self->set_value("path", $sBasePath);
    }

    $sPath= File::Spec->canonpath($sPath); # simplify path
    $sPath= File::Spec->rel2abs($sPath, $sBasePath) unless File::Spec->file_name_is_absolute($sPath);
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
    my $arMountMessages= shift;
    
    return 0 unless $sMountDevice;

    # if abs_path fails try original mount device (eg. samba shares)
    $sMountDevice= $self->abs_path($sMountDevice) || $sMountDevice;

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
