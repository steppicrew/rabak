#!/usr/bin/perl

package RabakLib::Type::File;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

use Data::Dumper;
use File::Spec;

sub _get_filter {
    my $self= shift;

    my $sFilter= $self->get_value('filter') ||
        ( "-(" . $self->get_value('exclude') . ") +(" . $self->get_value('include') . ")" );
    return $self->_parseFilter($sFilter);
}

sub _parseFilter {
    my $self= shift;
    my $sFilter= shift;

    my @sFilter= ();

    $sFilter=~ s/(?<!\\)([\-\+])\s+/$1/g; # remove spaces between +/- and path
    my @sIncExc= ();
    for (split /(?<!\\)[\s\,]+/, $sFilter) { # split on space or "," not preseeded by "\"
        my $sIncExc = '+';
        $sIncExc= $sIncExc[0] if scalar @sIncExc;
        $sIncExc= $1 if s/^([\-\+])//;
        unshift @sIncExc, $sIncExc if s/^\(//;
        shift @sIncExc or die "Filter rules contain unmatched closing bracket(s)" if s/(?<!\\)\)$//;
        for ($self->_expandFilterEntry($_)) {
            if (ref) {
                push @sFilter, "# Expanded from '" . $_->{start} . "'" if $_->{start};
                push @sFilter, "# End of '" . $_->{end} . "'" if $_->{end};
                push @sFilter, "# WARNING!! Recursive call of '" . $_->{recursion} . "'" if $_->{recursion};
                next;
            }
            my $isDir= /\/$/;
            $_= File::Spec->canonpath($_); # simplify path
            s/([^\/])$/$1\// if $isDir; # append "/" to directories (stripped by canonpath)
            s/\\([\s\,])/\[$1\]/g; # replace spaces with "[ ]"

            if (/^\/./ && $sIncExc eq '+') { # for includes add all parent directories
                my $sDir= '';
                for (split /(\/)/) {
                    $sDir.= "$_";
                    next if $sDir eq "/";
                    push @sFilter, "$sIncExc $sDir" if $_ eq "/"; # push directory
                }
                push @sFilter, "$sIncExc $sDir" unless $isDir; # push file (if file)
                next;
            }
            push @sFilter, "$sIncExc $_" if $_;
        }
    }
    die "Filter rules contain unmatched opening bracket(s)" if scalar @sIncExc;

    return @sFilter;
}

sub _expandFilterEntry {
    my $self= shift;
    my $sFilter= shift;
    my $hStack= shift || {};

    my @sFilter= ();
    for my $sSubFilter (split /(?<!\\)[\s\,]+/, $sFilter) {
        my $sMacro= $self->get_value($sSubFilter);
        if ($sMacro) {
            if ($hStack->{$sSubFilter}) {
                $self->log($self->warnMsg("Filter rules contain recursion ('$sSubFilter')"));
                push @sFilter, {recursion => $sSubFilter};
            }
            else {
                my $sF= $sSubFilter;
                my $sFEnd= '';
                $hStack->{$sSubFilter} = 1;
                push @sFilter, {start => $sSubFilter};
                push @sFilter, $self->_expandFilterEntry($sMacro, $hStack);
                push @sFilter, {end => $sSubFilter};
                delete($hStack->{$sSubFilter});
            }
        }
        else {
            push @sFilter, $sSubFilter;
        }
    }
    return @sFilter;
}

sub _show {
    my $self= shift;

    print "Expanded rsync filter:\n\t" . join("\n\t", $self->_get_filter) . "\n";
}

sub run {
    my $self= shift;
    my @sBakDir= @_;

    # print Dumper($self); die;

    # print '**'.$self->get_value('switch.pretend').'**'; die;

    my $sBakSet= $self->get_value('name');
    my $sRsyncOpts = $self->get_value('rsync_opts') || '';
    my $oTargetPath= $self->get_targetPath;
    my $sRsyncPass= $oTargetPath->get_value("passwd");
    my $sPort= $oTargetPath->get_value("port") || 22;
    my $sTimeout= $oTargetPath->get_value("timeout") || 150;
    my $sBandwidth= $oTargetPath->get_value("bandwidth") || 0;

    my $sSrc= $self->valid_source_dir() or return 3;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->tempfile();
    my ($fhwPass, $sPassFile);

    my @sFilter= $self->_get_filter;
    # print join("\n", @sFilter), "\n"; #die;

    print $fhwRules join("\n", @sFilter), "\n";
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
    if ($oTargetPath->remote) {
        $sFlags .= " -e 'ssh -p $sPort' --timeout='$sTimeout'";
        $sFlags .= " --bwlimit='$sBandwidth'" if $sBandwidth;
        if ($sRsyncPass) {
            ($fhwPass, $sPassFile)= $self->tempfile();
            print $fhwPass $sRsyncPass;
            close $fhwPass;
            $sFlags .= " --password-file=\"$sPassFile\""
        }
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    $sSrc .= "/" unless $sSrc =~ /\/$/;
    my $sDestDir= $oTargetPath->getPath($self->get_value("full_target"));
    if ($oTargetPath->remote) {
        $sDestDir= $oTargetPath->get_value("host") . ":$sDestDir";
        $sDestDir= $oTargetPath->get_value("user") . "\@$sDestDir" if $oTargetPath->get_value("user");
    }

    my $sRsyncCmd= "rsync $sFlags \"$sSrc\" \"$sDestDir\"";

    $self->log($self->infoMsg("Running: $sRsyncCmd"));

    # print Dumper($self); die;
    $oTargetPath->close if $oTargetPath->remote; # close ssh connection (will be opened if needed)

    my ($sRsyncOut, $sRsyncErr, $iRsyncExit, $sError)= $self->run_cmd($sRsyncCmd);
    $self->log($self->errorMsg($sError)) if $sError;
    $self->log($self->warnMsg("rsync exited with result ".  $iRsyncExit)) if $iRsyncExit;
    my @sRsyncError= split(/\n/, $sRsyncErr || '');
    $self->log($self->errorMsg(@sRsyncError)) if @sRsyncError;
    my @sRsyncStat= ();

    for (split(/\n/, $sRsyncOut || '')) {
        push @sRsyncStat, $_ unless /^([^\/]+\/)+$/;
    }

    my @sRsyncFiles= ();
    push @sRsyncFiles, shift @sRsyncStat while ((scalar @sRsyncStat) && $sRsyncStat[0] !~ /^Number of .*\:\s+\d+$/);

    $self->log([ 3, @sRsyncFiles ]);
    $self->log('*** Rsync Statistics: ***', @sRsyncStat);

    return 0;
}

1;

