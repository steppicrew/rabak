#!/usr/bin/perl

package Rabak::Util;

use warnings;
use strict;
no warnings 'redefine';

use Data::Dumper;
use Data::UUID;
use POSIX qw(strftime);

use Rabak::Conf;
use Rabak::Peer;

sub GetTimeString {
    return strftime("%Y%m%d%H%M%S", gmtime);
}

sub CreateUuid {
    return Data::UUID->new()->create_str();
}

sub GetControllerUuid {
    my $sControllerConfFile= GetVlrDir();
    my $oDevConf;
    my $sUuid;

    return undef unless defined $sControllerConfFile;

    $sControllerConfFile.= '/controller.cf';
    if (-f $sControllerConfFile) {
        my $oDevConfFile= Rabak::ConfFile->new($sControllerConfFile);
        $oDevConf= $oDevConfFile->conf();
        $sUuid= $oDevConf->getValue('uuid');
    }
    else {
        $oDevConf= Rabak::Conf->new('*');
    }
    unless ($sUuid) {
        # create new uuid and write into target's directory
        $sUuid= CreateUuid();
        $oDevConf->setQuotedValue('uuid', $sUuid);
        $oDevConf->writeToFile($sControllerConfFile);
    }
    return $sUuid;
}

sub GetVlrDir {
    my $sMetaDir= '/var/lib/rabak';
    return $sMetaDir if Rabak::Peer->new()->mkdir($sMetaDir);
    $sMetaDir= $ENV{HOME} . '/.rabak/meta' unless -d $sMetaDir && -w $sMetaDir;
    return $sMetaDir if Rabak::Peer->new()->mkdir($sMetaDir);
    return undef;
}

1;
