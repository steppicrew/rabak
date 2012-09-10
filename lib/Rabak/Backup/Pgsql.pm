#!/usr/bin/perl

package Rabak::Backup::Mongo;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Backup::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Backup::DBBase);

sub DEFAULT_USER {'root'};

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
    my $sTable= shift;

    my @result= (
        'pg_dump',
        '--clean',
        '--username=' . $self->getUser(),
    );

    push @result, '--table=' . $sTable if $sTable;

    push @result, $sDb;

    return @result;
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

sub parseValidTables {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidTables= ();
    for (split(/\n/, $sShowResult)) {
        $sValidTables{$1}= 1 if /^CREATE TABLE (\S+) \(/;
    }
    return %sValidTables;
}

1;
