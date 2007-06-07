#!/usr/bin/perl

package RabakLib::Type::File;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

use Data::Dumper;

sub run {
    my $self= shift;
    my @sBakDir= @_;

    # print Dumper($self); die;

    # print '**'.$self->get_value('switch.pretend').'**'; die;

    my $sBakSet= $self->get_value('name');
    my $sRsyncOpts = $self->get_value('rsync_opts') || '';
    my $oTarget= $self->get_target;
    my $sRsyncPass= $oTarget->get_value("passwd");

    my $sSrc= $self->valid_source_dir() or return 3;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->tempfile();
    my ($fhwPass, $sPassFile);

    my $sInclude= $self->get_value('include') || '';
    my $sExclude= $self->get_value('exclude') || '';

    for (split(/,\s+|\n/, $sExclude)) {
        s/^\s+//;
        s/\s+$//;
        # $_= "/*" if $_ eq "/";
        print $fhwRules "- $_\n" if $_;
    }

    for (split(/,\s+|\n/, $sInclude)) {
        s/^\s+//;
        s/\s+$//;

        # rsync works top down, so include all containing directories:
        if (/^\/(.+\/)/) {
            my @sDir= split(/\//, $1);
            my $sDir= "/";
            for my $i (0 .. $#sDir) {
                $sDir .= $sDir[$i] . "/";
                print $fhwRules "+ $sDir\n";
            }
        }

        # let all directories end with /** to include subdirectories
        $_ .= '*' if /\/\*$/;
        $_ .= '**' if /\/$/;

        print $fhwRules "+ $_\n" if $_;
    }

    print $fhwRules "- /**\n" if $sInclude;

    close $fhwRules;

    # print `cat $sRulesFile`;

    my $sFlags= "-a"
        . " --hard-links"
        . " --filter=\". $sRulesFile\""
        . " --stats"
        . " --verbose"
    ;

    $sFlags .= " -i" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $self->get_value('switch.pretend');
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;
    if ($sRsyncPass) {
        ($fhwPass, $sPassFile)= $self->tempfile();
        print $fhwPass $sRsyncPass;
        close $fhwPass;
        $sFlags .= " --password-file=\"$sPassFile\""
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    $sSrc .= "/" unless $sSrc =~ /\/$/;
    my $sDestDir= $oTarget->getPath;
    my $childId;
    if ($oTarget->remote) {
        $sDestDir= $oTarget->get_value("host") . ":44556$sDestDir";
        $sDestDir= $oTarget->get_value("user") . "\@$sDestDir" if $oTarget->get_value("user");
        $sDestDir= "rsync://$sDestDir";
        $childId= fork;
        if (defined $childId) {
            unless ($childId) { # we are the child
                $oTarget->_sshcmd("rsync --daemon --no-detach --port=44556");
                exit;
            }
            print "$childId\n";
            sleep 20; # wait for starting up rsync daemon
            print "continueing...\n";
        }
        else {
            die "faild to fork child process";
        }
    }

    my $sRsyncCmd= "rsync $sFlags \"$sSrc\" \"$sDestDir\"";

    $self->log($self->infoMsg("Running: $sRsyncCmd"));

    # print Dumper($self); die;

    my @sRsyncStat= grep !/^([^\/]+\/)+$/, `$sRsyncCmd 2>&1`;

    kill 9, $childId if $childId; # kill rsync daemon

    my @sRsyncFiles= ();
    push @sRsyncFiles, shift @sRsyncStat while ($sRsyncStat[0] && $sRsyncStat[0] !~ /^\s+$/);
    push @sRsyncFiles, shift @sRsyncStat;

    $self->log([ 3, @sRsyncFiles ]);
    $self->log(@sRsyncStat);

    return 0;
}

1;

