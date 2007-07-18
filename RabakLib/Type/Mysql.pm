#!/usr/bin/perl

package RabakLib::Type::Mysql;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type::DumpDB;

@ISA = qw(RabakLib::Type::DumpDB);

use Data::Dumper;

sub _get_user {
    my $self= shift;
    my $sUser= $self->get_value('user', 'mysql');
    $sUser =~ s/[^a-z0-9_]//g;        # simple taint
    return $sUser;
}

sub _get_passwd {
    my $self= shift;
    my $sPassword= $self->get_value('password', 'mysql');
    $sPassword =~ s/\\\"//g;          # simple taint
    return $sPassword;
}

sub get_show_cmd {
    my $self= shift;
    my $sPassPar= $self->_get_passwd;
    $sPassPar = "-p\"$sPassPar\"" if $sPassPar;
    return "mysqlshow -u\"" . $self->_get_user . "\" $sPassPar";
}

sub get_probe_cmd {
    my $self= shift;
    my $sDb= shift;

    my $sPassword= $self->_get_passwd;
    my $sPassPar= '';
    $sPassPar = "-p\"{{PASSWORD}}\"" if $sPassword;
    my $sProbeCmd= "mysqldump -d -u\"" . $self->_get_user . "\" $sPassPar -r /dev/null \"$sDb\"";
    $self->log("Running probe: $sProbeCmd");
    $sProbeCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;
    return $sProbeCmd;
}

sub get_dump_cmd {
    my $self= shift;
    my $sDb= shift;

    my $sPassword= $self->_get_passwd;
    my $sPassPar= '';
    $sPassPar = "-p\"{{PASSWORD}}\"" if $sPassword;
    my $sDumpCmd= "mysqldump -a -e --add-drop-table --allow-keywords -q -u\"" . $self->_get_user . "\" $sPassPar --databases \"$sDb\"";
    $self->log("Running dump: $sDumpCmd");
    $sDumpCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;
    return $sDumpCmd;
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
