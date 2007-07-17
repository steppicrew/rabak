#!/usr/bin/perl

package RabakLib::Type::Pgsql;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

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

    my $sPgUser= $self->get_value('user', 'postgres') || '';
    $sPgUser =~ s/[^a-z0-9_]//g;        # simple taint
    $sPgUser = " -U \"$sPgUser\"" if $sPgUser;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    $oSourcePath->run_cmd("psql -X -q -t -l $sPgUser postgres")
    for (split(/\n/, $oSourcePath->get_last_out)) {
        $sValidDb{$1}= 1 if /(\S+)/ && $1 !~ /^template\d+$/;
    }

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

        my $sPgProbeCmd= "pg_dump -s $sPgUser -f /dev/null $_";
        $self->log("Running probe: $sPgProbeCmd");
        unless ($self->get_value('switch.pretend')) {
            $oSourcePath->run_cmd($sPgProbeCmd);
            if ($oSourcePath->get_last_exit) {
                my $sError= $oSourcePath->get_last_error;
                chomp $sError;
                $self->logError("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sPgDumpCmd= "pg_dump -c $sPgUser $_ 2> \"$sResultFile\" | $sZipCmd";
        $self->log("Running dump: $sPgDumpCmd");

        unless ($self->get_value('switch.pretend')) {
            $oSourcePath->run_cmd($sPgDumpCmd, 1);
            if ($oSourcePath->get_last_exit) {
                my $sRF= $oSourcePath->getLocalFile($sResultFile);
                my $sError= `cat \"$sRF\"`;
                chomp $sError;
                $self->logError("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
            else {
                $self->log($self->infoMsg("Copying dump \"" . $oSourcePath->get_last_out . "\" to \"" . $oTargetPath->getFullPath($sDestFile) ."\""));
                $oTargetPath->copyLoc2Rem($oSourcePath->get_last_out, $sDestFile);
                $self->logError($oTargetPath->get_error()) if $oTargetPath->get_error();
            }
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
