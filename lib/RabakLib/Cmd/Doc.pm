#!/usr/bin/perl;

package RabakLib::Cmd::Doc;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::Log;
# use Cwd;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak doc',
        'Displays the documentation included in the Rabak package.',
        'This is basicly an alias for "perldoc RabakLib::Doc".',
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0);

    $self->warnOptions([ ]);

    logger->print(`perldoc RabakLib::Doc`);
    return 1;
}

1;