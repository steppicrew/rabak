#!/usr/bin/perl

package RabakLib::Mountable;

use warnings;
use strict;
no warnings 'redefine';

use Data::Dumper;
use File::Spec ();
use File::Temp ();

# use RabakLib::Log;

use RabakLib::Mount;

=head1 DESCRIPTION

Mountable.pm is a class for local or remote file objects.
It provides mount operations.

=over 4

=cut

sub new {
    my $class= shift;
    my $oPeer= shift;
    
    my $self= {
        PEER => $oPeer,
        PATH_IS_ABSOLUTE => 0,
    };

    bless $self, $class;
}

sub getPeer {
    my $self= shift;
    return $self->{PEER};
}

sub sort_show_key_order {
    my $self= shift;
    ("mount");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};

    my @oMounts= $self->getMountObjects();
    
    my @sSubResult= ();
    for my $oMount (@oMounts) {
        push @sSubResult, @{$oMount->show($hConfShowCache)};
    }
    return [] unless scalar @sSubResult;
    return ["", "# Referenced mounts:", @sSubResult, ];
}

sub getPath {
    my $self= shift;
    my $sPath= shift || '.';

    my $peer= $self->getPeer();

    my $sBasePath= $peer->get_value("path");

    return $sPath unless $sBasePath;

    # path may contain symlinks and should be expanded once
    unless ($self->{PATH_IS_ABSOLUTE}) {
        $sBasePath= $peer->abs_path($sBasePath);
        if (defined $sBasePath) {
            $peer->set_value("path", $sBasePath);
            $self->{PATH_IS_ABSOLUTE}= 1;
        }
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

    my $peer= $self->getPeer();

    # if abs_path fails try original mount device (eg. samba shares)
    $sMountDevice= $peer->abs_path($sMountDevice) || $sMountDevice;

    my $sqMountDevice= quotemeta $sMountDevice;

    my $cur_mounts= $peer->mount;
    # TODO:
    #     check for "mount" outputs different from '/dev/XXX on /mount/dir type ...' on other systems
    #     notice: the check for "type" after mount dir is because of missing delimiters if mount dir contains spaces!
    return $1 if $cur_mounts =~ /^$sqMountDevice\son\s+(\/.*)\stype\s/m;
    return 1;
}

sub getMountObjects {
    my $self= shift;

    my $peer= $self->getPeer();

    return () unless $peer->find_property("mount");

    my @oConfs= $peer->resolveObjects("mount");
    my @oMounts= ();
    for my $oConf (@oConfs) {
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' mounts: should this set parent for inheriting values?
            $oConf= RabakLib::Conf->new(undef, $peer);
            $oConf->set_value("directory", $sPath);
        }
        push @oMounts, RabakLib::Mount->newFromConf($oConf);
    } 
    return @oMounts;
}

# return
#       0: failed
#       1: succeeded
sub mountAll {
    my $self= shift;
    my $arMessage= shift || [];

    my $peer= $self->getPeer();

    my @aMounts= $self->getMountObjects();
    
    # Collect all mount errors, we want to output them later
    my $iResult= 1; # defaults to mount succeeded
    
    my $arAllMounts= [];

    for my $oMount (@aMounts) {
        $iResult = $oMount->mount($peer, $arMessage, $arAllMounts);
        # quit if mount failed
        # TODO: is this right for source objects?
        last if $peer->mountErrorIsFatal($iResult);
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
