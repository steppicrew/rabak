#!/usr/bin/perl

package RabakLib::Path::Source;

use warnings;
use strict;

use RabakLib::Log;

use vars qw(@ISA);

@ISA = qw(RabakLib::Path::Mountable);

sub Factory {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $sPath= $oOrigConf->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        my $sType= $1;
        my $sPrefType= $oOrigConf->get_value("type");
        logger->warn("Type in source path ($sType) differs from specified type ($sPrefType).") if $sPrefType && $sType ne $sPrefType;
        $oOrigConf->set_value("type", $sType);
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
        require "RabakLib/Path/Source/$sType.pm";
        my $sClass= "RabakLib::Path::Source::$sType";
        $new= $sClass->CloneConf($oOrigConf);
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            logger->error("Backup type \"$sType\" is not defined: $@");
        }
        else {
            logger->error("An error occured: $@");
        }
        return undef;
    }

    return $new;
}

sub getBaksetName {
    my $self= shift;
    my $sName= $self->get_value("name");
    $sName= "" unless defined $sName;
    $sName=~ s/^\*/source/;
    return $sName;
}

sub sort_show_key_order {
    my $self= shift;
    ("type", $self->SUPER::sort_show_key_order(), "keep");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};

    my @sResult= (
        "#" . "=" x 79,
        "# Source \"" . $self->getShowName() . "\": " . $self->getFullPath(),
        "#" . "=" x 79,
    );
    push @sResult, @{$self->SUPER::show($hConfShowCache)};
    return \@sResult;
}

sub getFullPath {
    my $self= shift;
    return $self->get_value("type") . "://" . $self->SUPER::getFullPath();
}

1;
