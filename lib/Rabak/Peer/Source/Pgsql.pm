#!/usr/bin/perl

package Rabak::Peer::Source::Pgsql;

use warnings;
use strict;
use vars qw(@ISA);

use Rabak::Peer::Source;
use Rabak::Peer::Source::DBBase;
use Rabak::Log;

@ISA = qw(Rabak::Peer::Source::DBBase);

sub _get_user {
    my $self= shift;
    my $sUser= $self->get_value('dbuser', 'postgres');
    $sUser =~ s/[^a-z0-9_]//g;        # simple taint
    return $sUser;
}

sub get_show_cmd {
    my $self= shift;

    return "psql --no-psqlrc --quiet --tuples-only --list --username " . $self->shell_quote($self->_get_user()) . " postgres";
}

sub get_probe_cmd {
    my $self= shift;
    my $sDb= $self->shell_quote(shift);

    my $sProbeCmd= "pg_dump --schema-only --username=" . $self->shell_quote($self->_get_user()) . " --file='/dev/null' $sDb";
    logger->info("Running probe: $sProbeCmd");
    return $sProbeCmd;
}

sub get_dump_cmd {
    my $self= shift;
    my $sDb= $self->shell_quote(shift);

    my $sDumpCmd= "pg_dump --clean --username=" . $self->shell_quote($self->_get_user()) . " $sDb";
    logger->info("Running dump: $sDumpCmd");
    return $sDumpCmd;
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
