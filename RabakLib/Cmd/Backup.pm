#!/usr/bin/perl;

package RabakLib::Cmd::Backup;

use warnings;
use strict;

use Data::Dumper;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub getOptions {
    return {
        # "targetgroup-value" =>  [ "",  "s", "<value>",   "Save on device with targetgroup value <value>" ],
        # "ha" =>                 [ "",  "",  "",          "HA" ],
    };
}

sub help {
    shift;
    my $sOptions= shift;
    return <<__EOT__;
rabak [options] backup <backup set>

Takes the given <backup set> and makes a backup.

The settings for the backup set must be in the configuration file, either the
default one or the one defined by then "--conf" option.
$sOptions
__EOT__
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0, 1);

    print "TBD!\n";

    return 1;
}

1;
