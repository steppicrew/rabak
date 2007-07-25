#!/usr/bin/perl

package RabakLib::SourceType::File;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::SourcePath);

use Data::Dumper;
use File::Spec;

sub _init {
    my $self= shift;
    
    unless ($self->get_value("scan_bak_dirs")) {
        my $iScanBakDirs= $self->get_set_value("scan_bak_dirs");
        if (defined $iScanBakDirs) {
            $self->set_value("scan_bak_dirs", $iScanBakDirs);
            $self->log($self->warnMsg("Specifying scan_bak_dirs in bakset is deprecated. Please set 'scan_bak_dirs' in Source Object!"));
        }
    }
}

sub _get_filter {
    my $self= shift;

    my $sFilter= $self->remove_backslashes_part1($self->get_raw_value('filter')) || '';
    unless ($sFilter) {
        $sFilter.= " -(" . $self->remove_backslashes_part1($self->get_raw_value('exclude')) . ")" if $self->get_raw_value('exclude');
        $sFilter.= " +(" . $self->remove_backslashes_part1($self->get_raw_value('include')) . ")" if $self->get_raw_value('include');
    }
    return $self->_parseFilter($sFilter, $self->valid_source_dir());
}

sub _expand {
    my $self= shift;
    my $sEntry= shift;
    my $hStack= shift || {};

    # remove spaces between +/- and path
    $sEntry=~ s/(?<!\\)([\-\+])\s+/$1/g;
    # enclose all macros with parantheses
    $sEntry=~ s/(?<!\\)(\&[\.\w]+)/\($1\)/g;
    $sEntry=~ s/(?<!\\)\(\s*/\( /g;
    $sEntry=~ s/(?<!\\)\s*\)/ \)/g;

    my @sEntries= split /(?<!\\)[\s\,]+/, $sEntry;

    my $hEntries= {
        TYPE => 'list',
        DATA => [],
    };
    my @arStack= ();
    for $sEntry (@sEntries) {
# print "Original: [$sEntry]\n";
        my $bClose= $sEntry=~ s/^\)//;
        my $bOpen= $sEntry=~ s/(?<!\\)\($//;

        # ')token'
        if ($bClose) {
            die "Closing bracket without opening!" unless scalar @arStack;
            $hEntries= pop @arStack;
        }
        # ' token('
        if ($bOpen && !$bClose) {
            my $hMixed= {
                TYPE => 'mixed',
                DATA => [],
            };
            push @{$hEntries->{DATA}}, $hMixed;
            push @arStack, $hEntries;
            $hEntries= $hMixed;
        }
        if ($sEntry =~ /^\&/) {
            my $hMacro= $self->_expandMacro($sEntry, $hStack);
            if ($hMacro->{ERROR}) {
                push @{$hEntries->{DATA}}, "# ERROR: $hMacro->{ERROR}";
            }
            else {
                die "Internal Error (List expected)" unless $hMacro->{DATA}{TYPE} eq 'list';
                push @{$hEntries->{DATA}}, "# Expanding '$hMacro->{MACRO}'";
                push @{$hEntries->{DATA}}, @{$hMacro->{DATA}{DATA}};
                push @{$hEntries->{DATA}}, "# End Of '$hMacro->{MACRO}'";
            }
        }
        else {
            push @{$hEntries->{DATA}}, $sEntry if $sEntry ne '';
        }
        # 'token('
        if ($bOpen) {
            my $sNewList= { TYPE => 'list', DATA => [], };
            push @{$hEntries->{DATA}}, $sNewList;
            push @arStack, $hEntries;
            $hEntries= $sNewList;
        }
        elsif ($hEntries->{TYPE} eq 'mixed') {
            $hEntries= pop @arStack;
            print "Internal Error(2) (List Expected)" unless $hEntries->{TYPE} eq 'list';
        }
    }
    die "Opening bracket without closing!" if scalar @arStack;
# print Dumper($hEntries);
    return $hEntries;
}

sub _expandMacro {
    my $self= shift;
    my $sMacroName= shift;
    my $hStack= shift || {};
    my %sResult= ();

# print "Expanding $sMacroName\n";

    $sMacroName=~ s/^\&//;
    if ($hStack->{$sMacroName}) {
        $sResult{ERROR}= "Recursion detected ('$sMacroName'). Ignored";
    }
    else {
        my $sMacro= $self->remove_backslashes_part1($self->get_set_raw_value($sMacroName));
        if (!$sMacro || ref $sMacro) {
            $sResult{ERROR}= "'$sMacroName' does not exist or is an object. Ignored.";
        }
        else {
            $sResult{MACRO}= $sMacroName;
            $hStack->{$sMacroName}= 1;
            $sResult{DATA}= $self->_expand($sMacro, $hStack);
            delete $hStack->{$sMacroName};
        }
    }
    $self->log($self->errorMsg("Filter expansion: $sResult{ERROR}")) if $sResult{ERROR};
#    return $sResult{DATA};
# print "Done $sMacroName\n";
    return \%sResult;
}

# flattens a list of filters like "/foo /foo/bar /bar"
sub _flatten_filter {
    my $self= shift;
    my $aFilter= shift;

    die "Internal Error: Filter List expected" unless $aFilter->{TYPE} eq 'list';
    my @sResult= ();
    for my $sEntry (@{$aFilter->{DATA}}) {
        if (ref $sEntry) {
            push @sResult, @{$self->_flatten_mixed_filter($sEntry)};
        }
        else {
            push @sResult, $sEntry;
        }
    }
    return \@sResult;
}

# flattens a combination of filters like "/foo/(bar1 bar2)/"
sub _flatten_mixed_filter {
    my $self= shift;
    my $aFilter= shift;

    die "Internal Error: Mixed Filter expected" unless $aFilter->{TYPE} eq 'mixed';
    my @sResult= ();
    for my $sEntry (@{$aFilter->{DATA}}) {
        if (ref $sEntry) {
            push @sResult, $self->_flatten_filter($sEntry);
        }
        else {
            push @sResult, [$sEntry];
        }
    }
    return \@sResult unless scalar @sResult;
    my $aTails= pop @sResult;
    while (my $aEntry= pop @sResult) {
        my $aNewTails= [];
        for my $sPrefix (@$aEntry) {
            # do not combine comments
            if ($sPrefix=~ /^\#/) {
                push @$aNewTails, $sPrefix;
                next;
            }
            for my $sSuffix (@$aTails) {
                # do not combine comments
                if ($sSuffix=~ /^\#/) {
                    push @$aNewTails, $sSuffix;
                    next;
                }
                # put +/- at beginning
# print "[$sPrefix] + [$sSuffix]";
                my ($sNewPrefix, $sNewSuffix)= ($sPrefix, $sSuffix);
                $sNewPrefix= "$1$sPrefix" if $sNewSuffix=~ s/^([\-\+]+)//;
# print " => [$sNewPrefix$sNewSuffix]\n";
                push @$aNewTails, "$sNewPrefix$sNewSuffix";
            }
        }
        $aTails = $aNewTails;
    }
    return $aTails;
}

sub _parseFilter {
    my $self= shift;
    my $sFilter= shift;
    my $sBaseDir= shift;
    
    $sBaseDir=~ s/\/?$/\//;
    my $sqBaseDir= quotemeta $sBaseDir;

    $sFilter= $self->_expand($sFilter);
# print Dumper($sFilter);
    my @sFilter= @{$self->_flatten_filter($sFilter)};

    return @sFilter unless scalar @sFilter;

    my %sIncDirs= ();
    my %sExcDirs= ();
    my @sResult= ();
    for my $sEntry (@sFilter) {
        $sEntry= $self->remove_backslashes_part2($sEntry);
        $sEntry=~ s/^([\-\+\#]*)\s*//;
        my $sIncExc= $1;

        my $isDir= $sEntry=~ /\/$/;
        # simplify path
        $sEntry= File::Spec->canonpath($sEntry);
        # append "/" to directories (stripped by canonpath)
        $sEntry=~ s/([^\/])$/$1\// if $isDir;

        unless ($sIncExc) {
            $self->log($self->warnMsg("'$sEntry' has no include/exclude prefix. Ignored."));
            push @sResult, "# WARNING!! '$sEntry' has no include/exclude prefix. Ignored.";
            next;
        }
        if (length $sIncExc > 1) {
            my $sSearchFor= $sIncExc=~ /^\+/ ? '-' : '+';
            if (index($sIncExc, $sSearchFor) >= 0) {
                $self->log($self->warnMsg("'$sEntry' has ambiguous include/exclude prefix. Ignored."));
                push @sResult, "# WARNING!! '$sEntry' has ambiguous include/exclude prefix. Ignored.";
                next;
            }
            $sIncExc=~ s/(?<=[\-\+]).*//;
        }

        if ($sEntry=~ /^\// && $sEntry!~ s/^$sqBaseDir/\//) {
            $self->log($self->warnMsg("'$sEntry' is not contained in source path '$sBaseDir'."));
            push @sResult, "# WARNING!! '$sEntry' is not contained in source path '$sBaseDir'. Ignored.";
            next;
        }
        # for includes add all parent directories
        if ($sEntry=~ /^\/./ && $sIncExc eq '+') {
            my $sDir= '';
            for (split /(\/)/, $sEntry) {
                $sDir.= "$_";
#                next if $sDir eq "/";
                unless ($sIncDirs{$sDir}) {
                    $self->log($self->warnMsg("Include '$sDir' is masked by exclude rule.")) if $sExcDirs{$sDir};
                    push @sResult, "$sIncExc $sDir" if $_ eq "/"; # push directory
                    $sIncDirs{$sDir}= 1;
                }
            }
            $sDir.= '**' if $isDir;
#            push @sResult, "$sIncExc $sDir" unless $isDir; # push file (if file)
            push @sResult, "$sIncExc $sDir";
            next;
        }
        # for excluded dirs add "***" to override includeded dirs from expanded includes (see above)
        # example: "+/zuppi/zappi, -/zuppi/" would be expanded to "+/zuppi/, +/zuppi/zappi, -/zuppi/***"
        # so all files except "zappi" under "/zuppi" are excluded (*** means this dir and all following
        # pathes)
        if ($sIncExc eq '-') {
            $sExcDirs{$sEntry}= 1 if $isDir;
            $sEntry=~ s/\/$/\/\*\*\*/;
        }
        push @sResult, "$sIncExc $sEntry" if $sEntry;
    }

    return @sResult;
}

sub _show {
    my $self= shift;

    return unless $self->get_set_value("switch.verbose") > 3;

    my $sBaseDir= $self->valid_source_dir();
    print "Expanded rsync filter (relative to '$sBaseDir'):\n\t" . join("\n\t", $self->_get_filter) . "\n";
}

sub valid_source_dir {
    my $self= shift;

    my $sSourceDir= $self->getFullPath;

    if (!$self->isDir) {
        $self->logError("Source \"$sSourceDir\" is not a directory. Backup set skipped.");
        return undef;
    }
    if (!$self->isReadable) {
        $self->logError("Source \"$sSourceDir\" is not readable. Backup set skipped.");
        return undef;
    }

    return $self->getPath;
}

sub run {
    my $self= shift;
    my @sBakDir= @_;

    return 3 unless $self->valid_source_dir;

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

    # run rsync command on source by default
    my $oRsyncPath= $self;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->local_tempfile();

    my @sFilter= $self->_get_filter;
    # print join("\n", @sFilter), "\n"; #die;

    print $fhwRules join("\n", @sFilter), "\n";
    close $fhwRules;

    # copy filter rules to source if target AND source are remote
    if ($oTargetPath->remote && $self->remote) {
        my $sRemRulesFile= $self->tempfile;
        $self->copyLoc2Rem($sRulesFile, $sRemRulesFile);
        $sRulesFile = $sRemRulesFile;
    }

    # print `cat $sRulesFile`;

    my $sFlags= "-a"
        . " --hard-links"
        . " --filter=\". $sRulesFile\""
        . " --stats"
        . " --verbose"
    ;

    $sFlags .= " -i" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $self->get_set_value('switch.pretend');
    if ($sRsyncOpts=~ s/\-\-bwlimit\=(\d+)//) {
        $sBandwidth= $1 unless $sBandwidth;
        $self->log($self->warnMsg("--bandwidth in 'rsync_opts' is deprecated. Please use 'bandwidth' option (see Doc)!"));
    }
    if ($sRsyncOpts=~ s/\-\-timeout\=(\d+)//) {
        $sTimeout= $1 unless $oTargetPath->get_value("timeout");
        $self->log($self->warnMsg("--timeout in 'rsync_opts' is deprecated. Please use 'timeout' option (see Doc)!"));
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
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    my $sSrcDir = $self->getPath . "/";
    my $sDestDir= $oTargetPath->getPath($self->get_set_value("full_target"));
    if ($oTargetPath->remote) {
        $sDestDir= $oTargetPath->get_value("host") . ":$sDestDir";
        $sDestDir= $oTargetPath->get_value("user") . "\@$sDestDir" if $oTargetPath->get_value("user");
    }
    else {
        # if target is local and src remote, build remote rsync path for source and run rsync locally
        if ($self->remote) {
            $sSrcDir= $self->get_value("host") . ":$sSrcDir";
            $sSrcDir= $self->get_value("user") . "\@$sSrcDir" if $self->get_value("user");
            $oRsyncPath= $oTargetPath;
        }
    }

    my $sRsyncCmd= "rsync $sFlags \"$sSrcDir\" \"$sDestDir\"";

    $self->log($self->infoMsg("Running: $sRsyncCmd"));

    # run rsync command
    my ($sRsyncOut, $sRsyncErr, $iRsyncExit, $sError)= $oRsyncPath->run_cmd($sRsyncCmd);
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

    return $iRsyncExit;
}

1;

