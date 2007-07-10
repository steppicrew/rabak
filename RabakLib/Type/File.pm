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

    my $sFilter= $self->get_value('filter') || '';
    unless ($sFilter) {
        $sFilter.= " -(" . $self->get_value('exclude') . ")" if $self->get_value('exclude');
        $sFilter.= " +(" . $self->get_value('include') . ")" if $self->get_value('include');
    }
    return $self->_parseFilter($sFilter, $self->valid_source_dir());
}

sub _parseFilter {
    my $self= shift;
    my $sFilter= shift;
    my $sBaseDir= shift;
    my $sIncExcDefault= shift || '+';
    my $hStack= shift || {};

    my @sFilter= ();
    $sBaseDir=~ s/\/?$/\//;
    my $sqBaseDir= quotemeta $sBaseDir;

    $sFilter=~ s/(?<!\\)([\-\+])\s+/$1/g; # remove spaces between +/- and path
    my @sIncExc= ();
    for (split /(?<!\\)[\s\,]+/, $sFilter) { # split on space or "," not preceeded by "\"
        my $sIncExc = $sIncExcDefault;
        $sIncExc= $sIncExc[0] if scalar @sIncExc;
        $sIncExc= $1 if s/^([\-\+])//;
        unshift @sIncExc, $sIncExc if s/^\(//;
        shift @sIncExc or die "Filter rules contain unmatched closing bracket(s)" if s/(?<!\\)\)$//;

        if (s/^\&//) { # expandable macro
            my $sMacro= $self->get_value($_);
            if (!$sMacro || ref $sMacro) {
                $self->log($self->errorMsg("'$_' does not exist or is an object. Ignoring."));
                push @sFilter, "# WARNING!! '$_' does not exist or is an object. Ignored.";
            }
            elsif ($hStack->{$_}) {
                $self->log($self->errorMsg("Filter rules contain recursion ('$_')"));
                push @sFilter, "# WARNING!! Recursive call of '$_'. Ignored.";
            }
            else {
                $hStack->{$_} = 1;
                push @sFilter, "# Expanded from '$_'";
                push @sFilter, $self->_parseFilter($sMacro, $sBaseDir, $sIncExc, $hStack);
                push @sFilter, "# End of '$_'";
                delete($hStack->{$_});
            }
        }
        else {
            my $isDir= /\/$/;
            $_= File::Spec->canonpath($_); # simplify path
            s/([^\/])$/$1\// if $isDir; # append "/" to directories (stripped by canonpath)
            if (/^\// && !s/^$sqBaseDir/\//) {
                $self->log($self->warnMsg("'$_' is not contained in source path '$sBaseDir'."));
                push @sFilter, "# WARNING!! '$_' is not contained in source path '$sBaseDir'. Ignored.";
                next;
            }
#            s/\\([\s\,])/\[$1\]/g; # replace spaces with "[ ]"
            s/\\([\s\,\&\+\-])/$1/g; # remove escape char

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

sub _show {
    my $self= shift;

    my $sBaseDir= $self->valid_source_dir();
    print "Expanded rsync filter (relative to '$sBaseDir'):\n\t" . join("\n\t", $self->_get_filter) . "\n";
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
    my $sBandwidth= $oTargetPath->get_value("bandwidth") || '';
    my @sIdentityFiles= $oTargetPath->get_value("identity_files") ? split(/\s+/, $oTargetPath->get_value("identity_files")) : undef;

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
    if ($sRsyncOpts=~ s/\-\-bwlimit\=(\d+)//) {
        $sBandwidth= $1 unless $sBandwidth;
        $self->log($self->warnMsg("--bandwidth in 'rsync_opts' is depricated.", "Please use 'bandwidth' option (see Doc)!"));
    }
    if ($sRsyncOpts=~ s/\-\-timeout\=(\d+)//) {
        $sTimeout= $1 unless $oTargetPath->get_value("timeout");
        $self->log($self->warnMsg("--timeout in 'rsync_opts' is depricated.", "Please use 'timeout' option (see Doc)!"));
    }
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;
    if ($oTargetPath->remote) {
        my $sSshCmd= "ssh -p $sPort";
        map { $sSshCmd.= " -i \"$_\"" if $_; } @sIdentityFiles if @sIdentityFiles;
        if ($oTargetPath->get_value("protocol")) {
            $sSshCmd.= " -1" if $oTargetPath->get_value("protocol") eq "1";
            $sSshCmd.= " -2" if $oTargetPath->get_value("protocol") eq "2";
        }
        $sFlags .= " -e '$sSshCmd' --timeout='$sTimeout'";
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

    my ($sRsyncOut, $sRsyncErr, $iRsyncExit, $sError)= RabakLib::Path->savecmd($sRsyncCmd);
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

