#!/usr/bin/perl

package Rabak::Peer::Source::Mysql;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Peer::Source;
use Rabak::Peer::Source::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Peer::Source::DBBase);

use Data::Dumper;

sub DEFAULT_USER {'mysql'};

# returns credentials save for logging
sub _get_credentials {
    my $self= shift;
    
    my @sResult= (
        "--user=" . $self->get_user(),
    );
    push @sResult, " --password='{{PASSWORD}}'" if defined $self->get_passwd();
    return @sResult;
}

sub get_show_cmd {
    my $self= shift;
    return ("mysqlshow", $self->_get_credentials());
}

sub get_probe_cmd {
    my $self= shift;
    my $sDb= shift;

    return ('mysqldump', '--no-data', $self->_get_log_credentials(), '--result-file=/dev/null', $sDb);
}

sub get_dump_cmd {
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
    push @sResult, '--flush-logs' if $self->get_value("dbflushlogs", 1);
    push @sResult, '--databases', $sDb;

    return @sResult;
}

sub parse_valid_db {
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
