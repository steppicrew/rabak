#!/usr/bin/perl;

package Rabak::Cmd::Doc;

use warnings;
use strict;

use Data::Dumper;
use Rabak::Log;
# use Cwd;

use vars qw(@ISA);

@ISA= qw( Rabak::Cmd );

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak doc',
        'Displays the documentation included in the Rabak package.',
        'This is basicly an alias for "perldoc Rabak::Doc".',
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0);

    $self->warnOptions([ ]);

    logger->print(`perldoc Rabak::Doc`);
    return 1;
}

1;
