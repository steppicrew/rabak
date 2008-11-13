#!/usr/bin/perl

package RabakLib::Peer::Source::DBBase;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::Peer::Source);

use Data::Dumper;
use RabakLib::Log;

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

sub sort_show_key_order {
    my $self= shift;
    ($self->SUPER::sort_show_key_order(), "dbuser", "dbpassword")
}


# TODO
# plan: build a tunnel, fetch the db, delete old baks, release tunnel
# TODO: option dump_oids
# TODO: support large objects (pg_dump -Fc)
sub run {
    my $self= shift;
    my $oTargetPeer= shift;
    my $bPretend= shift;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $self->run_cmd($self->get_show_cmd);
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
        my $sDestFile= $oTargetPeer->getAbsBakDir()
            . "/$_."
            . $oTargetPeer->getSourceSubdir()
            . ".$sZipExt";
        my $sProbeCmd= $self->get_probe_cmd($_);

        unless ($bPretend) {
            $self->run_cmd($sProbeCmd);
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                logger->error("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sDumpCmd= $self->get_dump_cmd($_) . " | $sZipCmd";

        my $oDumpPeer= $self;
        my $sPipeCmd= "cat > '$sDestFile'";

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
        unless ($bPretend) {
            $oDumpPeer->run_cmd("$sDumpCmd | $sPipeCmd");
            if ($oDumpPeer->get_last_exit) {
                my $sError= $oDumpPeer->get_last_error;
                chomp $sError;
                logger->error("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
