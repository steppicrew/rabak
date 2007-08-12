#!/usr/bin/perl

package RabakLib::Path::Source;

use warnings;
use strict;

use RabakLib::Log;
use FindBin qw($Bin);

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub Factory {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $sPath= $oOrigConf->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        $oOrigConf->set_value("type", $1);
        $oOrigConf->set_value("path", $sPath);
    }
    my $sType= $oOrigConf->get_value("type");
    unless (defined $sType) {
       $sType= "file" unless $sType;
       $oOrigConf->set_value("type", $sType);
    } 
    $sType= ucfirst $sType;

    my $new;
    eval {
        require "$Bin/RabakLib/SourceType/$sType.pm";
        my $sClass= "RabakLib::SourceType::$sType";
        $new= $sClass->CloneConf($oOrigConf);
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            logger->error("Backup type \"" . $sType . "\" is not defined: $@");
        }
        else {
            logger->error("An error occured: $@");
        }
        return undef;
    }

    return $new;
}

sub show {
    my $self= shift;
    my $sKey= shift || '';
    my $hConfShowCache= shift || {};

    my $sName= $self->get_value("name");
    $self->SUPER::show($sKey, $hConfShowCache);# unless $sName=~ /^\*/;
}

sub getFullPath {
    my $self= shift;
    return $self->get_value("type") . "://" . $self->SUPER::getFullPath();
}

1;
