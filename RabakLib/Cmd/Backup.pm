#!/usr/bin/perl;

package RabakLib::Cmd::Backup;

use warnings;
use strict;

use Data::Dumper;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub getOptions {
    return {
        "targetgroup-value" =>  [ "",  "s", "<value>",   "Save on device with targetgroup value <value>" ],
    };
}

sub help {
    shift;
    my $sOptions= shift;
    return <<__EOT__;
rabak backup [options] <backup set>

Takes the given <backup set> and makes a backup.

The settings for the backup set must be in the configuration file, either the
default one or the one defined by the "--conf" option.
$sOptions
__EOT__
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(1);

    my $sBakset= $self->{ARGS}[0];
    my $oBakset= $self->getBakset($sBakset);
    return 0 unless $oBakset;
    
    $oBakset->set_value('/*.switch.targetvalue', $self->{OPTS}{"targetgroup-value"}) if $self->{OPTS}{"targetgroup-value"};

    $oBakset->backup();
    return 1;
}

1;
