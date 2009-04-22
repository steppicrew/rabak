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
        'rabak backup [options] <job name>',
        'Takes the given <job name> and makes a backup.',
        'The settings for the job must be in the configuration file, either the',
        'default one or the one defined by the ' . colored("--conf", "bold") . ' option.',
        '',
        'To list all available jobs use ' . colored("rabak conf [--conf <file>]", "bold"),
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(1);

    my $sJob= $self->{ARGS}[0];
    my $oJob= $self->getJob($sJob);
    return 0 unless $oJob;
    
    $oJob->setValue('/*.switch.targetvalue', $self->{OPTS}{"targetgroup-value"}) if defined $self->{OPTS}{"targetgroup-value"};
    $oJob->setValue('/*.switch.logging', $self->{OPTS}{logging}) if defined $self->{OPTS}{logging};

    $oJob->backup();
    return 1;
}

1;
