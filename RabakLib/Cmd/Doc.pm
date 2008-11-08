#!/usr/bin/perl;

package RabakLib::Cmd::Doc;

use warnings;
use strict;

use Data::Dumper;
# use Cwd;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub help {
    shift;
    my $sOptions= shift;
    return <<__EOT__;
rabak doc

Displays the documentation included in the Rabak package.

This is basicly an alias for "perldoc RabakLib::Doc".

__EOT__
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0);

    print `perldoc RabakLib::Doc`;
    return 1;
}

1;
