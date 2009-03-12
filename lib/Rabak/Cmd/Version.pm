#!/usr/bin/perl;

package Rabak::Cmd::Version;

use warnings;
use strict;
use vars qw(@ISA);

use Data::Dumper;
use Rabak::Version;
use Rabak::Log;

@ISA= qw( Rabak::Cmd );

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
    
    logger->print(Rabak::Version::LongVersionMsg(), $/);
    return 1;
}

1;
