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
# TODO: dump *to* remote host
# TODO: dump *from* remote host
sub run {
    my $self= shift;
    my @sBakDir= @_;

    die "Dumps to remote hosts are not supported!\n" if $self->get_targetPath->remote;

    my $sPgUser= $self->get_value('user', 'postgres') || '';
    $sPgUser =~ s/[^a-z0-9_]//g;        # simple taint
    $sPgUser = " -U \"$sPgUser\"" if $sPgUser;

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    for (split(/\n/, `psql -X -q -t -l $sPgUser postgres`)) {
        $sValidDb{$1}= 1 if /(\S+)/ && $1 !~ /^template\d+$/;
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

        my $sPgProbeCmd= "pg_dump -s $sPgUser -f /dev/null $_ 2>&1";
        $self->log("Running probe: $sPgProbeCmd");
        my $sError= `$sPgProbeCmd` unless $self->get_value('switch.pretend');
        if ($sError) {
            chomp $sError;
            $self->logError("Probe failed. Skipping \"$_\": $sError");
            next;
        }

        my $sPgDumpCmd= "pg_dump -c $sPgUser $_ 2> \"$sResultFile\" | $sZipCmd > \"$sDestFile\"";
        $self->log("Running dump: $sPgDumpCmd");

        `$sPgDumpCmd` unless $self->get_value('switch.pretend');
        $sError= `cat \"$sResultFile\"`;
        if ($sError) {
            chomp $sError;
            $self->logError("Dump failed. Skipping dump of \"$_\": $sError");
            next;
        }
        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;
