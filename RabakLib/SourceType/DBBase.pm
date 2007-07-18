#!/usr/bin/perl

package RabakLib::SourceType::DBBase;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::SourcePath;

@ISA = qw(RabakLib::Type);

use Data::Dumper;

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
# TODO: dump *from* remote host
sub run {
    my $self= shift;
    my @sBakDir= @_;

    my $oTargetPath= $self->get_targetPath;
    my $oSourcePath= $self->get_sourcePath;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $oSourcePath->run_cmd($self->get_show_cmd);
    if ($oSourcePath->get_last_exit) {
        $self->log($self->errorMsg("show databases command failed with: " . $oSourcePath->get_error));
        return 9;
    }
    %sValidDb= $self->parse_valid_db($oSourcePath->get_last_out);

    my $sSource= $oSourcePath->get_value("db");

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

    # TODO: make configurable
    my $sZipCmd= "bzip2";
    my $sZipExt= "bz2";

    my $sResultFile= $oSourcePath->tempfile();

    foreach (@sDb) {
        my $sDestFile= $self->get_value('full_target') . "/$_." . $self->get_value('unique_target') . ".$sZipExt";
        my $sProbeCmd= $self->get_probe_cmd($_);

        unless ($self->get_value('switch.pretend')) {
            $oSourcePath->run_cmd($sProbeCmd);
            if ($oSourcePath->get_last_exit) {
                my $sError= $oSourcePath->get_last_error;
                chomp $sError;
                $self->logError("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sDumpCmd= $self->get_dump_cmd($_) . " 2> $sResultFile | $sZipCmd";
        if ($oTargetPath->remote || $oSourcePath->remote) {
            $sDumpCmd= $oSourcePath->_ssh->build_ssh_cmd($sDumpCmd);
        }
        unless ($self->get_value('switch.pretend')) {
            $oTargetPath->run_cmd("$sDumpCmd > $sDestFile");
            if ($oSourcePath->get_last_exit) {
                my $sRF= $oSourcePath->getLocalFile($sResultFile);
                my $sError= `cat \"$sRF\"`;
                chomp $sError;
                $self->logError("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
            else {
#                $self->log($self->infoMsg("Copying dump \"" . $oSourcePath->get_last_out . "\" to \"" . $oTargetPath->getFullPath($sDestFile) ."\""));
#                $oTargetPath->copyLoc2Rem($oSourcePath->get_last_out, $sDestFile);
#                $self->logError($oTargetPath->get_error()) if $oTargetPath->get_error();
            }
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
