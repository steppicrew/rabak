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
    push @sResult, " --password='{{PASSWORD}}'" if defined $self->getPasswd();
    return @sResult;
}

sub getShowCmd {
    my $self= shift;
    return ("mysqlshow", $self->_getCredentials());
}

sub getProbeCmd {
    my $self= shift;
    my $sDb= shift;

    return ('mysqldump', '--no-data', $self->_getCredentials(), '--result-file=/dev/null', $sDb);
}

sub getDumpCmd {
    my $self= shift;
    my $sDb= shift;

    my @sResult= (
        'mysqldump',
        '--all',
        '--extended-insert',
        '--add-drop-table',
        '--allow-keywords'.
        '--quick',
        '--single-transaction',
    );
    push @sResult, '--flush-logs' if $self->getValue("dbflushlogs", 1);
    push @sResult, '--databases', $sDb;

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
    return %sValidDb;
}

1;