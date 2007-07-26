#!/usr/bin/perl

package RabakLib::SourceType::DBBase;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::Path::Source);

use Data::Dumper;

sub new {
    my $class = shift;
    my $self= $class->SUPER::new(@_);
    
    our %sPackers = (
        bzip2 => { cmd => "bzip2", ext => "bz2"},
        gzip => { cmd => "gzip", ext => "gz"},
    );
    
    unless ($self->get_value("dbuser")) {
        my $sUser= $self->get_set_value("user");
        if (defined $sUser) {
            $self->set_value("dbuser", $sUser);
            $self->log($self->warnMsg("Specifying database user name in bakset is deprecated. Please set 'dbuser' in Source Object!"));
        }
    }
    unless ($self->get_value("dbpassword")) {
        my $sPasswd= $self->get_set_value("password");
        if (defined $sPasswd) {
            $self->set_value("dbpassword", $sPasswd);
            $self->log($self->warnMsg("Specifying database password in bakset is deprecated. Please set 'dbpassword' in Source Object!"));
        }
    }

    my $sPacker= lc $self->get_value("packer");
    $self->log($self->warnMsg("Unknown packer '$sPacker'. Valid Values are: '" .
        join("', '", keys %sPackers) . 
        "'. Using default 'bzip2'")) if $sPacker && !$sPackers{$sPacker};
    $sPacker= "bzip2" unless $sPacker && $sPackers{$sPacker};
    $self->{PACKER} = $sPackers{$sPacker};
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
    my @sBakDir= @_;

    my $oTargetPath= $self->get_targetPath();

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $self->run_cmd($self->get_show_cmd);
    if ($self->get_last_exit) {
        $self->log($self->errorMsg("show databases command failed with: " . $self->get_error));
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
                $self->log($self->warnMsg("Unknown database: \"$_\""));
                next;
            }
            unshift @sDb, $_;
        }
    }

    my $sZipCmd= $self->{PACKER}{cmd};
    my $sZipExt= $self->{PACKER}{ext};

    foreach (@sDb) {
        my $sDestFile= $self->get_set_value('full_target') . "/$_." . $self->get_set_value('unique_target') . ".$sZipExt";
        my $sProbeCmd= $self->get_probe_cmd($_);

        unless ($self->get_global_set_value('switch.pretend')) {
            $self->run_cmd($sProbeCmd);
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                $self->logError("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sDumpCmd= $self->get_dump_cmd($_) . " | $sZipCmd";
        if ($oTargetPath->remote || $self->remote) {
            # TODO: check if target and source are the same users on the same host
            $sDumpCmd= $self->_ssh->build_ssh_cmd($sDumpCmd);
        }
        unless ($self->get_global_set_value('switch.pretend')) {
            $oTargetPath->run_cmd("$sDumpCmd > $sDestFile");
            if ($self->get_last_exit) {
                my $sError= $self->get_last_error;
                chomp $sError;
                $self->logError("Dump failed. Skipping dump of \"$_\": $sError");
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
