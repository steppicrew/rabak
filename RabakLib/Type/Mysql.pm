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
#    die "Dumps to remote hosts are not supported!\n" if $oTargetPath->remote;

    $sUser =~ s/[^a-z0-9_]//g;        # simple taint
    $sPassword =~ s/\\\"//g;          # simple taint
    $sPassPar = "-p\"$sPassword\"" if $sPassword;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    for (split(/\n/, `mysqlshow -u"$sUser" $sPassPar`)) {
        $sValidDb{$1}= 1 if $i++ >= 3 && /^\|\s+(.+?)\s+\|$/;
    }

    if ($self->get_value('source') eq '*') {
        @sDb= sort keys %sValidDb;
    }
    else {
        for (split(/\s*,\s*/, $self->get_value('source'))) {
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

    my ($fhwResult, $sResultFile)= $self->tempfile();

    foreach (@sDb) {
        my $sDestFile= $self->get_value('full_target') . "/$_." . $self->get_value('unique_target') . ".$sZipExt";
        my $sDumpFile= $sDestFile;
        if ($oTargetPath->remote) {
            my $fh;
            ($fh, $sDumpFile)= $oTargetPath->tempfile();
            close $fh;
        }
        $sPassPar = "-p\"{{PASSWORD}}\"" if $sPassword;
        my $sProbeCmd= "mysqldump -d -u\"$sUser\" $sPassPar -r /dev/null \"$_\" 2>&1";
        $self->log("Running probe: $sProbeCmd");
        $sProbeCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;
        my $sError= `$sProbeCmd` unless $self->get_value('switch.pretend');
        if ($sError) {
            chomp $sError;
            $self->logError("Probe failed. Skipping \"$_\": $sError");
            next;
        }

        my $sDumpCmd= "mysqldump -a -e --add-drop-table --allow-keywords -q -u\"$sUser\" $sPassPar --databases \"$_\" 2> \"$sResultFile\" | $sZipCmd > \"$sDumpFile\"";
        $self->log("Running dump: $sDumpCmd");
        $sDumpCmd =~ s/\{\{PASSWORD\}\}/$sPassword/;

        unless ($self->get_value('switch.pretend')) {
            `$sDumpCmd`;
            if ($oTargetPath->remote) {
                $self->log($self->infoMsg("Copying dump \"$sDumpFile\" to \"" . $oTargetPath->getFullPath($sDestFile) ."\""));
                $oTargetPath->copyLoc2Rem($sDumpFile, $sDestFile);
                $self->logError($oTargetPath->get_error()) if $oTargetPath->get_error();
            }
            $sError= `cat \"$sResultFile\"`;
            if ($sError) {
                chomp $sError;
                $self->logError("Dump failed. Skipping dump of \"$_\": $sError");
                next;
            }
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
