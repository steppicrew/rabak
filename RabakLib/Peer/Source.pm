#!/usr/bin/perl

package RabakLib::Peer::Source;

use warnings;
use strict;

use RabakLib::Log;

use vars qw(@ISA);

@ISA = qw(RabakLib::Peer);

=head1 DESCRIPTION

Source.pm is an abstract class for source objects (file, databases etc.).
It provides a static method 'Factory' to create specialized source objects 

=over 4

=cut

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
       $sType= "file";
       $oOrigConf->set_value("type", $sType);
    } 
    $sType= ucfirst lc $sType;

    my $new;
    eval {
        require "RabakLib/Peer/Source/$sType.pm";
        my $sClass= "RabakLib::Peer::Source::$sType";
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

sub getPathExtension {
    my $self= shift;
    my $sName= $self->get_value("path_extension", $self->get_value("name", ""));
    $sName=~ s/^\*/source/;
    return "" if $sName eq "";
    return ".$sName";
}

# TODO: is there a better way to call parallel objects?
sub sort_show_key_order {
    my $self= shift;
    my $fSuper= shift;
    
    my @sSuperResult= ();
    if ($fSuper) {
        @sSuperResult= $fSuper->();
    }
    else {
        @sSuperResult= $self->SUPER::sort_show_key_order();
    }
    ("type", @sSuperResult, "keep");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    my $fSuper= shift;
    
    my @sSuperResult= ();
    if ($fSuper) {
        @sSuperResult= @{$fSuper->($hConfShowCache)};
    }
    else {
        @sSuperResult= @{$self->SUPER::show($hConfShowCache)};
    }

    return [] unless @sSuperResult;

    return [
        "",
        "#" . "=" x 79,
        "# Source \"" . $self->getShowName() . "\": " . $self->getFullPath(),
        "#" . "=" x 79,
        @sSuperResult
    ];
}

sub getFullPath {
    my $self= shift;
    return $self->get_value("type") . "://" . $self->SUPER::getFullPath();
}

1;
