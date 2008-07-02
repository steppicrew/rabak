#!/usr/bin/perl

package RabakLib::Peer::Source::Mysql;

use warnings;
use strict;
use vars qw(@ISA);

use RabakLib::Peer::Source;
use RabakLib::Peer::Source::DBBase;
use RabakLib::Log;

@ISA = qw(RabakLib::Peer::Source::DBBase);

use Data::Dumper;

sub _get_user {
    my $self= shift;
    my $sUser= $self->get_value('dbuser', 'mysql');
    # simple taint
    $sUser =~ s/[^a-z0-9_]//g;
    return $sUser;
}

sub _get_passwd {
    my $self= shift;
    my $sPassword= $self->get_value('dbpassword', '');
    return $sPassword;
}

# returns credentials save for logging
sub _get_log_credentials {
    my $self= shift;
    
    my $sPassword= $self->_get_passwd();
    my $sResult= "--user=" . $self->shell_quote($self->_get_user());
    $sResult.= " --password='{{PASSWORD}}'" if defined $sPassword;
    return $sResult;
}

# returns credentials with password logging
sub _get_credentials {
    my $self= shift;
    
    my $sResult= $self->_replace_password($self->_get_log_credentials());
}

# logs passwordless command (optional) and inserts real password
sub _replace_password {
    my $self= shift;
    my $sCommand= shift || $self->_get_log_credentials();
    my $sLog= shift;
    
    logger->info("$sLog: $sCommand") if $sLog;
    my $sPassword= $self->_get_passwd();
    $sCommand=~ s/\{\{PASSWORD\}\}/$sPassword/ if defined $sPassword;
    return $sCommand;
}

sub get_show_cmd {
    my $self= shift;
    return "mysqlshow " . $self->_get_credentials();
}

sub get_probe_cmd {
    my $self= shift;
    my $sDb= $self->shell_quote(shift);

    my $sProbeCmd= "mysqldump --no-data " . $self->_get_log_credentials() . " --result-file='/dev/null' $sDb";
    return $self->_replace_password($sProbeCmd, "Running probe");
}

sub get_dump_cmd {
    my $self= shift;
    my $sDb= $self->shell_quote(shift);

    my $sParamFlush= $self->get_value("dbflushlogs", 1) ? " --flush-logs" : "";
    my $sDumpCmd= "mysqldump --all --extended-insert --add-drop-table --allow-keywords --quick " . $self->_get_log_credentials() . "$sParamFlush --databases $sDb";
    return $self->_replace_password($sDumpCmd, "Running dump");
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
