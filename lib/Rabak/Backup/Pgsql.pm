#!/usr/bin/perl

package Rabak::Backup::Pgsql;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Backup::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Backup::DBBase);

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

    push @result, map { '--exclude-schema=' . $_ } grep { $_ } split(/\s*,\s*/, $self->_getSourceValue("exclude_schema", ''));

    push @result, map { '--exclude-table=' . $_ } grep { $_ } split(/\s*,\s*/, $self->_getSourceValue("exclude_table", ''));

    push @result, $sDb;

    return @result;
}

sub parseValidDb {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidDb= ();
    for (split(/\n/, $sShowResult)) {
        $sValidDb{$1}= 1 if /^\s*([^\s\|]+)/ && $1 !~ /^template\d+$/;
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
