#!/usr/bin/perl

package Rabak::Peer::Source::DBBase;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(Rabak::Peer::Source);

use Data::Dumper;
use Rabak::Log;

our %sPackers = (
    bzip2 => { cmd => "bzip2", ext => "bz2"},
    gzip  => { cmd => "gzip" , ext => "gz"},
);

sub newFromConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::newFromConf($oOrigConf);

    my $sPacker= lc $new->get_value("packer");

    logger->warn("Unknown packer '$sPacker'. Valid Values are: '"
        . join("', '", keys %sPackers)
        . "'. Using default 'bzip2'") if $sPacker && !$sPackers{$sPacker};

    $sPacker= "bzip2" unless $sPacker && $sPackers{$sPacker};
    $new->{PACKER} = $sPackers{$sPacker};

    return $new;
}

sub DEFAULT_USER {
    die "This function has to be overloaded!"
}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return (shift->SUPER::PropertyNames(), 'dbuser', 'dbpassword');
}

sub get_show_cmd {
    die "This function has to be overloaded!"
}

sub get_probe_cmd {
    die "This function has to be overloaded!"
}

sub get_dump_cmd {
    die "This function has to be overloaded!"
}

sub get_valid_db {
    die "This function has to be overloaded!"
}

sub get_user {
    my $self= shift;
    my $sUser= $self->get_value('dbuser', $self->DEFAULT_USER());
    # simple taint
    $sUser =~ s/[^a-z0-9_]//g;
    return $sUser;
}

sub get_passwd {
    my $self= shift;
    my $sPassword= $self->get_value('dbpassword');
    return $sPassword;
}

sub build_run_cmd {
    my $self= shift;
    my @sCommand= @_;
    
    my $sPassword= $self->get_passwd;
    
    my $sCommand= $self->shell_quote(@sCommand);
    $sCommand=~ s/\{\{PASSWORD\}\}/$sPassword/ if defined $sPassword;
    return $sCommand;
}

sub _run_cmd {
    my $self= shift;
    my @sCommand= @_;
    $self->run_cmd($self->build_run_cmd(@sCommand));
}

sub log_cmd {
    my $self= shift;
    my $sLogPretext= shift;
    my @sCommand= @_;
    
    logger->info($sLogPretext . ': ' . $self->shell_quote(@sCommand));
}

# TODO
# plan: build a tunnel, fetch the db, delete old baks, release tunnel
# TODO: option dump_oids
# TODO: support large objects (pg_dump -Fc)
sub run {
    my $self= shift;
    my $oTargetPeer= shift;
    my $hMetaInfo= shift;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $self->_run_cmd($self->get_show_cmd());
    if ($self->get_last_exit) {
        logger->error("show databases command failed with: " . $self->get_error);
        return 9;
    }
    %sValidDb= $self->parse_valid_db($self->get_last_out);

    my $sSource= $self->get_value("path");

    if ($sSource eq '*') {
        @sDb= sort keys %sValidDb;
    }
    else {
        for (split(/\s*,\s*/, $sSource)) {
            unless (defined $sValidDb{$_}) {
                logger->warn("Unknown database: \"$_\"");
                next;
            }
            unshift @sDb, $_;
        }
    }

    my $sZipCmd= $self->{PACKER}{cmd};
    my $sZipExt= $self->{PACKER}{ext};

    foreach (@sDb) {
        my $sDestFile= $hMetaInfo->{DATA_DIR} . "/$_.$sZipExt";
        my @sProbeCmd= $self->get_probe_cmd($_);
        $self->log_cmd('Running probe', @sProbeCmd);

        unless ($self-pretend()) {
            $self->_run_cmd(@sProbeCmd);
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                logger->error("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my @sDumpCmd= $self->get_dump_cmd($_);
        $self->log_cmd('Running dump', @sDumpCmd, '|', $sZipCmd);

        my $oDumpPeer= $self;
        my $sPipeCmd= "cat > '$sDestFile'";
        
        my $sDumpCmd= $self->build_run_cmd(@sDumpCmd) . " | " . $self->shell_quote($sZipCmd);

        if ($oTargetPeer->is_remote()) {
            # if target is remote, dump on source peer and write output remotely to target
            # TODO: check if target and source are the same users on the same host
            $sPipeCmd= $oTargetPeer->build_ssh_cmd($sPipeCmd);
        }
        elsif ($self->is_remote()) {
            # if target is local and soure is remote, dump over ssh and write directly to file
            $oDumpPeer= $oTargetPeer;
            $sDumpCmd= $self->build_ssh_cmd($sDumpCmd);
        }

        # now execute dump command on target
        unless ($self->pretend()) {
            $oDumpPeer->run_cmd("$sDumpCmd | $sPipeCmd");
            if ($oDumpPeer->get_last_exit) {
                my $sError= $oDumpPeer->get_last_error;
                chomp $sError;
                logger->error("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
            $hMetaInfo->{FILE_CALLBACK}->($sDestFile) if $hMetaInfo->{FILE_CALLBACK};
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
