#!/usr/bin/perl;

package RabakLib::Cmd::Dot;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::SetDot;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak dot [options] <backup set>',
        'one liner',
        'description',
    );
}

sub run {
    my $self= shift;

    # $self->warnOptions([ 'quiet', 'verbose', 'pretend' ]);

    die "'dot' defunct due to interface changes is Set";

    $self->wantArgs(1);

    my $sBakset= $self->{ARGS}[0];

    my $oBakset= $self->getBakset($sBakset);
    return 0 unless $oBakset;

    $self->warnOptions([ ]);

    my $oDot= RabakLib::SetDot->new($oBakset);
    $oDot->toDot();     # FIXME: toDot should be called run

    return 1;
}

1;
