#!/usr/bin/perl

package Rabak::Peer::Source::Pgsql;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Peer::Source;
use Rabak::Peer::Source::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Peer::Source::DBBase);

sub DEFAULT_USER {'postgres'};

sub getShowCmd {
    my $self= shift;

    return (
        'psql',
        '--no-psqlrc',
        '--tuples-only',
        '--list',
        '--username', $self->getUser(),
        'postgres',
    );
}

sub getProbeCmd {
    my $self= shift;
    my $sDb= shift;

    return (
        'pg_dump',
        '--schema-only',
        '--username=' . $self->getUser(),
        '--file=/dev/null',
        $sDb,
    );
}

sub getDumpCmd {
    my $self= shift;
    my $sDb= shift;

    return (
        'pg_dump',
        '--clean',
        '--username=' . $self->getUser(),
        $sDb,
    );
}

sub parseValidDb {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidDb= ();
    for (split(/\n/, $sShowResult)) {
        $sValidDb{$1}= 1 if /(\S+)/ && $1 !~ /^template\d+$/;
    }
    return %sValidDb;
}

1;
