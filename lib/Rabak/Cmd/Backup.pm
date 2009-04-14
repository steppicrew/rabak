#!/usr/bin/perl;

package Rabak::Cmd::Backup;

use warnings;
use strict;

use Data::Dumper;
use Term::ANSIColor;

use vars qw(@ISA);

@ISA= qw( Rabak::Cmd );

sub getOptions {
    return {
        "targetgroup-value" =>  [ "i", "=s", "<value>",   "Save on device with targetgroup value <value>" ],
        "logging" =>            [ "l", "!",  "",          "Force or prevent logging even if specified otherwise in config file." ],
    };
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak backup [options] <backup set>',
        'Takes the given <backup set> and makes a backup.',
        'The settings for the backup set must be in the configuration file, either the',
        'default one or the one defined by the ' . colored("--conf", "bold") . ' option.',
        '',
        'To list all available backup sets use ' . colored("rabak conf [--conf <file>]", "bold"),
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(1);

    my $sBakset= $self->{ARGS}[0];
    my $oBakset= $self->getBakset($sBakset);
    return 0 unless $oBakset;
    
    $oBakset->setValue('/*.switch.targetvalue', $self->{OPTS}{"targetgroup-value"}) if defined $self->{OPTS}{"targetgroup-value"};
    $oBakset->setValue('/*.switch.logging', $self->{OPTS}{logging}) if defined $self->{OPTS}{logging};

    $oBakset->backup();
    return 1;
}

1;
