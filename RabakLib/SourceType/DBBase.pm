#!/usr/bin/perl

package RabakLib::SourceType::DBBase;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::Path::Source);

use Data::Dumper;
use RabakLib::Log;

our %sPackers = (
    bzip2 => { cmd => "bzip2", ext => "bz2"},
    gzip  => { cmd => "gzip" , ext => "gz"},
);

sub cloneConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::cloneConf($oOrigConf);

    my $sPacker= lc $new->get_value("packer");
    logger->warn("Unknown packer '$sPacker'. Valid Values are: '" .
        join("', '", keys %sPackers) . 
        "'. Using default 'bzip2'") if $sPacker && !$sPackers{$sPacker};
    $sPacker= "bzip2" unless $sPacker && $sPackers{$sPacker};
    $new->{PACKER} = $sPackers{$sPacker};

    return $new;
}

sub new {
    my $class = shift;
    my $self= $class->SUPER::new(@_);
    
    bless $self, $class;
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


# TODO
# plan: build a tunnel, fetch the db, delete old baks, release tunnel
# TODO: option dump_oids
# TODO: support large objects (pg_dump -Fc)
sub run {
    my $self= shift;
    my $oTargetPath= shift;
    my $sFullTarget= shift;
    my $sUniqueTarget= shift;
    my @sBakDir= @_;


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
        my $sDestFile= "$sFullTarget/$_.$sUniqueTarget.$sZipExt";
        my $sProbeCmd= $self->get_probe_cmd($_);

        unless ($self->get_value('switch.pretend')) {
            $self->run_cmd($sProbeCmd);
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                logger->error("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sDumpCmd= $self->get_dump_cmd($_) . " | $sZipCmd";

        # target executes $sDumpCmd on source (may be remote from targets view) to
        # pipe stdout/stderr to final target file
        # therefore we have to build a ssh command, if either target or source
        # is remote
        if ($oTargetPath->is_remote() || $self->is_remote()) {
            # TODO: check if target and source are the same users on the same host
            $sDumpCmd= $self->build_ssh_cmd($sDumpCmd);
        }

        # now execute dump command on target
        unless ($self->get_value('switch.pretend')) {
            $oTargetPath->run_cmd("$sDumpCmd > $sDestFile");
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                logger->error("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

sub getPath {
    my $self= shift;
    my $sPath= shift || $self->get_value("path");

    return $sPath;
}

1;
