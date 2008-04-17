#!/usr/bin/perl

package RabakLib::Path::Source::File;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::Path::Source);

use Data::Dumper;
use File::Spec;
use RabakLib::Log;

# hash table for detecting references and list of all used macros in filter expansion
sub _get_filter {
    my $self= shift;
    my $aMacroStack= shift || [];
    my $oTarget= shift;

    my $sFilter= $self->get_raw_value('filter'); 
    
    # target path is always excluded
    my $aFilter= [];
    if ($oTarget) {
        push @$aFilter, "-" . $oTarget->getPath();
    }
    if (defined $sFilter) {
        push @$aFilter, "&filter";
    }
    else {
        push @$aFilter, "-(", "&exclude", ")" if defined $self->get_raw_value('exclude');
        push @$aFilter, "+(", "&include", ")" if defined $self->get_raw_value('include');
    }
    return $self->_parseFilter($aFilter, $self->valid_source_dir(), $aMacroStack);
}

# parse filter string in $sFilter
# returns array with rsync's include/exclude rules
sub _parseFilter {
    my $self= shift;
    my $aFilter= shift;
    my $sBaseDir= shift;
    my $aMacroStack= shift || [];
    
    return () unless defined $sBaseDir;
    
    $sBaseDir=~ s/\/?$/\//;
    my $sqBaseDir= quotemeta $sBaseDir;

    my $sFilter= $self->_expand($aFilter, $self, $aMacroStack);
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
            logger->warn("'$sEntry' has no include/exclude prefix. Ignored.");
            push @sResult, "# WARNING!! '$sEntry' has no include/exclude prefix. Ignored.";
            next;
        }
        if (length $sIncExc > 1) {
            my $sSearchFor= $sIncExc=~ /^\+/ ? '-' : '+';
            if (index($sIncExc, $sSearchFor) >= 0) {
                logger->warn("'$sEntry' has ambiguous include/exclude prefix. Ignored.");
                push @sResult, "# WARNING!! '$sEntry' has ambiguous include/exclude prefix. Ignored.";
                next;
            }
            $sIncExc=~ s/(?<=[\-\+]).*//;
        }

        if ($sEntry=~ /^\// && $sEntry!~ s/^$sqBaseDir/\//) {
            logger->debug("'$sEntry' is not contained in source path '$sBaseDir'.");
            push @sResult, "# Notice: '$sEntry' is not contained in source path '$sBaseDir'. Ignored.";
            next;
        }
        # for includes add all parent directories
        if ($sEntry=~ /^\/./ && $sIncExc eq '+') {
            my $sDir= '';
            for (split /(\/)/, $sEntry) {
                $sDir.= "$_";
#                next if $sDir eq "/";
                unless ($sIncDirs{$sDir}) {
                    logger->warn("Include '$sDir' is masked by exclude rule.") if $sExcDirs{$sDir};
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
        # paths)
        if ($sIncExc eq '-') {
            $sExcDirs{$sEntry}= 1 if $isDir;
            $sEntry=~ s/\/$/\/\*\*\*/;
        }
        push @sResult, "$sIncExc $sEntry" if $sEntry;
    }

    return @sResult;
}

# internal filter structure:
#   filter types:
#       "list": simple array of filter entries (strings or "mixed" filter)
#       "mixed": list of filter "list"s to be combined

# expands filter string in $sEntry
# return hashref of type 'list'
sub _expand {
    my $self= shift;
    my $aEntries= shift;
    my $oScope= shift || $self;
    my $aMacroStack= shift || [];

#print "expanding: [".join("n", @$aEntries)."]\n";

    my $hEntries= {
        TYPE => 'list',
        DATA => [],
    };
    my @arStack= ();
    for my $sEntry (@$aEntries) {
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
            my $hMacro= $self->expandMacro($sEntry, $oScope, $aMacroStack,
                sub {$self->_expand(@_)}, # function to expand macro's content
                sub{ # function to modify macro's text before splitting
                    my $sEntry= shift;
                    # remove spaces between +/- and path
                    $sEntry=~ s/(?<!\\)([\-\+])\s+/$1/g;
                    # enclose all macros with parantheses
                    $sEntry=~ s/(?<!\\)(\&[\.\w]+)/\($1\)/g;
                    # add space after '('
                    $sEntry=~ s/(?<!\\)\(\s*/\( /g;
                    # add space before ')'
                    $sEntry=~ s/(?<!\\)\s*\)/ \)/g;
                    return $sEntry;
                },
            );
            if ($hMacro->{ERROR}) {
                logger->error("Filter expansion: $hMacro->{ERROR}");
                push @{$hEntries->{DATA}}, "# ERROR: $hMacro->{ERROR} Ignored.";
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

# flattens a list of filters like "/foo /foo/bar /bar"
sub _flatten_filter {
    my $self= shift;
    my $hFilter= shift;

    die "Internal Error: Filter List expected" unless $hFilter->{TYPE} eq 'list';
    my @sResult= ();
    for my $sEntry (@{$hFilter->{DATA}}) {
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
    my $hFilter= shift;

    die "Internal Error: Mixed Filter expected" unless $hFilter->{TYPE} eq 'mixed';
    my @aResult= ();
    for my $sEntry (@{$hFilter->{DATA}}) {
        if (ref $sEntry) {
            push @aResult, $self->_flatten_filter($sEntry);
        }
        else {
            push @aResult, [$sEntry];
        }
    }
    return \@aResult unless scalar @aResult;
    # take last array of @sResult as first result @sTail
    # combine every entry of the last array of @sResult with every entry of result's array @sTail
    my $aTails= pop @aResult;
    while (my $aEntry= pop @aResult) {
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
                my ($sNewPrefix, $sNewSuffix)= ($sPrefix, $sSuffix);
                $sNewPrefix= "$1$sPrefix" if $sNewSuffix=~ s/^([\-\+]+)//;
                push @$aNewTails, "$sNewPrefix$sNewSuffix";
            }
        }
        $aTails = $aNewTails;
    }
    return $aTails;
}

sub sort_show_key_order {
    my $self= shift;
    ($self->SUPER::sort_show_key_order(), "exclude", "include", "filter", "mount");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    my $oTarget= shift;
    
    my $aResult = $self->SUPER::show($hConfShowCache, $oTarget);
    
    my $aMacroStack= [];

    my @sFilter= $self->_get_filter($aMacroStack, $oTarget);
    my $sLastScope= "";
    my @sSubResult= ();
    for my $sMacroName ($self->get_all_references($aMacroStack)) {
        push @sSubResult, $self->showConfValue($sMacroName, $hConfShowCache);
    }
    push @$aResult, "", "# Referenced filters:", @sSubResult if scalar @sSubResult;
    push @$aResult, "[]" unless $sLastScope eq "";
    
    shift @$aMacroStack if scalar @$aMacroStack;
    push @{$hConfShowCache->{'.'}}, @$aMacroStack;
    
    return $aResult unless $self->get_switch("logging") >= LOG_DEBUG_LEVEL;

    my $sBaseDir= $self->valid_source_dir();
    push @$aResult, "", "# Expanded rsync filter (relative to '$sBaseDir'):", map {"#\t$_"} @sFilter;
    return $aResult;
}

sub valid_source_dir {
    my $self= shift;

    my $sSourceDir= $self->getFullPath();

    if (!$self->isDir()) {
        logger->error("Source \"$sSourceDir\" is not a directory. Backup set skipped.");
        return undef;
    }
    if (!$self->isReadable()) {
        logger->error("Source \"$sSourceDir\" is not readable. Backup set skipped.");
        return undef;
    }

    return $self->getPath;
}

sub _run_rsync {
    my $self = shift;
    my $oRsyncPath = shift || $self;
    my $sSrc = shift or die "_run_rsync: No source specified";
    my $sDst = shift or die "_run_rsync: No target specified";
    my $sFlags = shift || '';
    my $hHandles = shift || {};
    
    $sSrc =  $self->shell_quote($sSrc);
    $sDst =  $self->shell_quote($sDst);
    my $sRsyncCmd= "rsync $sFlags $sSrc $sDst";

    logger->info("Running" .
        ($oRsyncPath->is_remote() ?
            " on '" . $oRsyncPath->getUserHostPort() . "'" :
            "") .
        ": $sRsyncCmd");
    logger->incIndent();

    # run rsync command
    my (undef, undef, $iExit, $sError)= $oRsyncPath->run_cmd($sRsyncCmd, $hHandles);

    logger->decIndent();
    logger->error($sError) if $sError;
    if ($iExit) {
        logger->warn("rsync exited with result $iExit");
        return $iExit;
    }
    logger->info("rsync finished successfully");
    return 0;    
}

sub run {
    my $self= shift;
    my $oTargetPath= shift;
    my $sFullTarget= shift;
    my $sUniqueTarget= shift;
    my $bPretend= shift;
    my @sBakDir= @_;

    return 3 unless $self->valid_source_dir();

    # print Dumper($self); die;

    # print '**$bPretend**'; die;

    # Unused: my $sBakSet= $self->get_value('name');

    my $sRsyncOpts = $self->get_value('rsync_opts') || '';

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->local_tempfile();

    my @sFilter= $self->_get_filter(undef, $oTargetPath);
    # print join("\n", @sFilter), "\n"; #die;

    print $fhwRules join("\n", @sFilter), "\n";
    close $fhwRules;

    # copy filter rules to source if target AND source and remote
    if ($oTargetPath->is_remote() && $self->is_remote()) {
        my $sRemRulesFile= $self->tempfile;
        $self->copyLocalFileToRemote($sRulesFile, $sRemRulesFile);
        $sRulesFile = $sRemRulesFile;
    }

    # print `cat $sRulesFile`;

    my $sFlags= "--archive"
        . " --sparse"
        . " --hard-links"
        . " --filter='. " . $self->shell_quote($sRulesFile, 'dont quote') . "'"
        . " --stats"
        . " --verbose"
    ;

    $sFlags .= " --itemize-changes" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $bPretend;
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;
    
    # $oSshPeer contains ssh parameters for rsync (seen from executing location)
    # - is TargetPath if target is remote (rsync will be run on SourcePath)
    # - is SourcePath if target is local and source is remote (rsync will be run locally)
    # $oRsyncPath contains path rsync is running from
    # - is TargetPath if target is local and source is remote
    # - is SourcePath otherwise
    my $oSshPeer;
    my $oRsyncPath = $self;
    my $sSrcDirPref = "";
    my $sDstDirPref = "";
    if ($oTargetPath->is_remote()) {
        # unless target and source on same host/user/port
        unless ($oTargetPath->getUserHostPort() eq $self->getUserHostPort()) {
            $oSshPeer = $oTargetPath;
            $sDstDirPref= $oTargetPath->getUserHost(":");
        }
    }
    elsif ($self->is_remote()) {
        $oSshPeer= $self;
        $sSrcDirPref= $self->getUserHost(":");
        $oRsyncPath = $oTargetPath;
    }
    if ($oSshPeer) {
        my $sPort= $oSshPeer->get_value("port") || 22;
        my $sTimeout= $oSshPeer->get_value("timeout") || 150;
        my $sBandwidth= $oSshPeer->get_value("bandwidth") || '';
        my @sIdentityFiles= $oSshPeer->get_value("identity_files") ? split(/\s+/, $oSshPeer->get_value("identity_files")) : undef;

        if ($sRsyncOpts=~ s/\-\-bwlimit\=(\d+)//) {
            $sBandwidth= $1 unless $sBandwidth;
            logger->warn("--bandwidth in 'rsync_opts' is deprecated. Please use 'bandwidth' option (see Doc)!");
        }
        if ($sRsyncOpts=~ s/\-\-timeout\=(\d+)//) {
            $sTimeout= $1 unless $oTargetPath->get_value("timeout");
            logger->warn("--timeout in 'rsync_opts' is deprecated. Please use 'timeout' option (see Doc)!");
        }

        my $sSshCmd= "ssh -p $sPort";
        map { $sSshCmd.= " -i " . $self->shell_quote($_) if $_; } @sIdentityFiles if @sIdentityFiles;
        if ($oSshPeer->get_value("protocol")) {
            $sSshCmd.= " -1" if $oSshPeer->get_value("protocol") eq "1";
            $sSshCmd.= " -2" if $oSshPeer->get_value("protocol") eq "2";
        }
        $sFlags .= " --rsh='$sSshCmd' --timeout='$sTimeout'";
        $sFlags .= " --bwlimit='$sBandwidth'" if $sBandwidth;
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    my $sLinkFlags = "";
    map { $sLinkFlags .= " --link-dest=" . $self->shell_quote($_); } @sBakDir;

    my $sSrcDir = $self->getPath;

    # make sure path ends with "/"
    $sSrcDir=~ s/\/?$/\//;

    my $sDstDir= $oTargetPath->getPath($sFullTarget);

    # prepare handles for stdout/stderr
    my $sStdOutStat= 0;
    my @sLinkErrors= ();
    my $qDstDir= quotemeta $sDstDir;
    my %Handles= (
        STDOUT => sub {
            for my $sLine (@_) {
                chomp $sLine;
                # skip directory lines
                next if $sLine =~ /^([^\/]+\/)+$/;
                # detect some warnings
                if ($sLine =~ /^file has vanished\: \".*\"$/) {
                    logger->warn($sLine);
                    next;
                }
                if ($sLine =~ /^Number of .*\:\s+\d+$/) {
                    logger->info('*** Rsync Statistics: ***') unless $sStdOutStat;
                    $sStdOutStat= 1;
                }
                if ($sStdOutStat) {
                    logger->info($sLine);
                    next;
                }
                logger->verbose($sLine);
            } 
        },
        STDERR => sub {
            for my $sLine (@_) {
                chomp $sLine;
                if ($sLine =~ /^rsync\: link \"$qDstDir\/(.+)\" \=\> .+ failed\: Too many links/) {
                    push @sLinkErrors, $1;
                    logger->verbose($sLine);
                    next;
                }
                logger->error(@_);
            }
        },
    );

    # run rsync cmd
    my $iRsyncExit = $self->_run_rsync($oRsyncPath, $sSrcDirPref.$sSrcDir, $sDstDirPref.$sDstDir, $sFlags.$sLinkFlags, \%Handles);

    if (scalar @sLinkErrors) {
        logger->info("The following files could not be hard linked, trying again without --hard-links flag:");
        logger->incIndent();
        logger->info(@sLinkErrors);
        logger->decIndent();
        logger->info("Fixing hard link errors...");
        logger->incIndent();
        # Write failed link files to temp file:
        my ($fhwFiles, $sFilesFile)= $self->local_tempfile();
        print $fhwFiles join("\n", @sLinkErrors), "\n";
        close $fhwFiles;

        # copy files file to source if rsync is run remotely
        if ($oRsyncPath->is_remote()) {
            my $sRemFilesFile= $oRsyncPath->tempfile;
            $oRsyncPath->copyLocalFileToRemote($sFilesFile, $sRemFilesFile);
            $sFilesFile = $sRemFilesFile;
        }
        # reset StdOut flag for STDOUT handler
        $sStdOutStat= 0;
        # simple error handling only
        $Handles{STDERR} = sub {logger->error(@_)};

        # run rsync cmd (drop exit code - has been logged anyway)
        $self->_run_rsync($oRsyncPath, $sSrcDirPref.$sSrcDir, $sDstDirPref.$sDstDir,
            "$sFlags --files-from=" . $self->shell_quote($sFilesFile),
            \%Handles);

        logger->decIndent();
        logger->info("...done fixing hard link errors.");
    }

    # return success for partial transfer errors (errors were logged already above)
    return 0 if $iRsyncExit == 23 || $iRsyncExit == 24;
    return $iRsyncExit;
}

1;

