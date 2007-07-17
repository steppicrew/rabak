#!/usr/bin/perl

package RabakLib::Type::Mysql;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

use Data::Dumper;

# TODO
# plan: build a tunnel, fetch the db, delete old baks, release tunnel
# TODO: option dump_oids
# TODO: support large objects (pg_dump -Fc)
# TODO: dump *from* remote host
sub run {
    my $self= shift;
    my @sBakDir= @_;

    my $sUser= $self->get_value('user', 'mysql');
    my $sPassword= $self->get_value('password', 'mysql');
    my $sPassPar = "";

    my $oTargetPath= $self->get_targetPath;
    my $oSourcePath= $self->get_sourcePath;

    $sUser =~ s/[^a-z0-9_]//g;        # simple taint
    $sPassword =~ s/\\\"//g;          # simple taint
    $sPassPar = "-p\"$sPassword\"" if $sPassword;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $oSourcePath->run_cmd("mysqlshow -u\"$sUser\" $sPassPar");
    if ($oSourcePath->get_last_exit) {
        $self->log($self->errorMsg("command mysql failed with: " . $oSourcePath->get_error));
        return 9;
    }
    for (split(/\n/, $oSourcePath->get_last_out)) {
        $sValidDb{$1}= 1 if $i++ >= 3 && /^\|\s+(.+?)\s+\|$/;
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
        $sPassPar = "-p\"{{PASSWORD}}\"" if $sPassword;
        my $sProbeCmd= "mysqldump -d -u\"$sUser\" $sPassPar -r /dev/null \"$_\"";
        $self->log("Running probe: $sProbeCmd");
        $sProbeCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;
        unless ($self->get_value('switch.pretend')) {
            $oSourcePath->run_cmd($sProbeCmd);
            if ($oSourcePath->get_last_exit) {
                my $sError= $oSourcePath->get_last_error;
                chomp $sError;
                $self->logError("Probe failed. Skipping \"$_\": $sError");
                next;
            }
        }

        my $sDumpCmd= "mysqldump -a -e --add-drop-table --allow-keywords -q -u\"$sUser\" $sPassPar --databases \"$_\" 2> \"$sResultFile\" | $sZipCmd";
        $self->log("Running dump: $sDumpCmd");
        $sDumpCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;

        unless ($self->get_value('switch.pretend')) {
            $oSourcePath->run_cmd($sDumpCmd, 1);
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
