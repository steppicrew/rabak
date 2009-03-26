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

sub get_show_cmd {
    my $self= shift;

    return (
        'psql',
        '--no-psqlrc',
        '--tuples-only',
        '--list',
        '--username', $self->get_user(),
        'postgres',
    );
}

sub get_probe_cmd {
    my $self= shift;
    my $sDb= shift;

    return (
        'pg_dump',
        '--schema-only',
        '--username=' . $self->get_user(),
        '--file=/dev/null',
        $sDb,
    );
}

sub get_dump_cmd {
    my $self= shift;
    my $sDb= shift;

    return (
        'pg_dump',
        '--clean',
        '--username=' . $self->get_user(),
        $sDb,
    );
}

sub parse_valid_db {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidDb= ();
    for (split(/\n/, $sShowResult)) {
        $sValidDb{$1}= 1 if /(\S+)/ && $1 !~ /^template\d+$/;
    }
    return %sValidDb;
}

1;
