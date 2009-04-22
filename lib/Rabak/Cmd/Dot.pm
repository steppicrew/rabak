#!/usr/bin/perl;

package Rabak::Cmd::Dot;

use warnings;
use strict;

use Data::Dumper;
use Rabak::JobDot;

use vars qw(@ISA);

@ISA= qw( Rabak::Cmd );

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak dot [options] <job name>',
        'one liner',
        'description',
    );
}

sub run {
    my $self= shift;

    # $self->warnOptions([ 'quiet', 'verbose', 'pretend' ]);

    die "'dot' defunct due to interface changes is Job";

    $self->wantArgs(1);

    my $sJob= $self->{ARGS}[0];

    my $oJob= $self->getJob($sJob);
    return 0 unless $oJob;

    $self->warnOptions([ ]);

    my $oDot= Rabak::JobDot->new($oJob);
    $oDot->toDot();     # FIXME: toDot should be called run

    return 1;
}

1;
