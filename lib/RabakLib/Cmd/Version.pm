#!/usr/bin/perl;

package RabakLib::Cmd::Version;

use warnings;
use strict;
use vars qw(@ISA);

use Data::Dumper;
use RabakLib::Version;
use RabakLib::Log;

@ISA= qw( RabakLib::Cmd );

sub getOptions {
    return {};
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak version',
        'Shows rabak\'s version and copyright notes.',
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0);

    $self->warnOptions([ ]);
    
    logger->print(RabakLib::Version::LongVersionMsg(), $/);
    return 1;
}

1;
