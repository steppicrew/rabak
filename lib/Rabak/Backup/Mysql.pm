#!/usr/bin/perl

package Rabak::Backup::Mysql;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Backup::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Backup::DBBase);

use Data::Dumper;

sub DEFAULT_USER {'mysql'};

# returns credentials save for logging
sub _getCredentials {
    my $self= shift;

    my @sResult= (
        "--user=" . $self->getUser(),
    );
    push @sResult, '--password={{PASSWORD}}' if defined $self->getPasswd();
    return @sResult;
}

sub getShowCmd {
    my $self= shift;
    return ("mysqlshow", $self->_getCredentials());
}

sub getProbeCmd {
    my $self= shift;
    my $sDb= shift;

    my @sResult= ('mysqldump', '--no-data', $self->_getCredentials());
    push @sResult, '--host', $self->_getSourceValue("dbhost") if $self->_getSourceValue("dbhost");
    push @sResult, $sDb;

    return @sResult;
}

sub getDumpCmd {
    my $self= shift;
    my $sDb= shift;
    my $sTable= shift;

    my @sResult= (
        'mysqldump',
        '--create-options',
        '--extended-insert',
        '--add-drop-table',
        '--allow-keywords',
        '--quick',
        '--single-transaction',
        '--skip-comments',
        '--skip-lock-table',
        $self->_getCredentials(),
    );
    push @sResult, '--host', $self->_getSourceValue("dbhost") if $self->_getSourceValue("dbhost");
    push @sResult, '--flush-logs' if $self->_getSourceValue("dbflushlogs", 1);
    push @sResult, '--databases', $sDb;
    push @sResult, '--tables', $sTable if $sTable;

    return @sResult;
}

sub parseValidDb {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidDb= ();
    my $i= 0;
    for (split(/\n/, $sShowResult)) {
        $sValidDb{$1}= 1 if $i++ >= 3 && /^\|\s+(.+?)\s+\|$/;
    }

    # remove dbs "information_schema" and "performance_schema", because they cannot be backed up
    delete $sValidDb{information_schema};
    delete $sValidDb{performance_schema};
    return %sValidDb;
}

sub parseValidTables {
    my $self= shift;
    my $sShowResult= shift;

    my %sValidTables= ();
    for (split(/\n/, $sShowResult)) {
        $sValidTables{$1}= 1 if /^CREATE TABLE \`?(\S+?)\`? \(/;
    }
    return %sValidTables;
}

1;
