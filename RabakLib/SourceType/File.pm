#!/usr/bin/perl

package RabakLib::SourceType::File;

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
    my $hMacroStack= shift || {};

    my ($sFilter, $oFilterParent)= $self->get_property('filter'); 
    if (defined $sFilter && ! ref $sFilter) {
        my $sFilterName= $oFilterParent->get_full_name('filter');
        $hMacroStack->{$sFilterName}= 1;
        $sFilter= $self->remove_backslashes_part1($sFilter);
    }
    else {
        $sFilter="";
        $sFilter.= " -(" . $self->remove_backslashes_part1($self->get_raw_value('exclude')) . ")" if $self->get_raw_value('exclude');
        $sFilter.= " +(" . $self->remove_backslashes_part1($self->get_raw_value('include')) . ")" if $self->get_raw_value('include');
    }
    return $self->_parseFilter($sFilter, $self->valid_source_dir(), $hMacroStack);
}

sub _expand {
    my $self= shift;
    my $sEntry= shift;
    my $hMacroStack= shift || {};

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
            my $hMacro= $self->_expandMacro($sEntry, $hMacroStack);
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
    my $hMacroStack= shift || {};

    my %sResult= ();

# print "Expanding $sMacroName\n";

    $sMacroName=~ s/^\&//;
    my ($sMacro, $oMacroParent)= $self->get_property($sMacroName); 
    $sMacroName= $oMacroParent->get_full_name($sMacroName);
    if ($hMacroStack->{$sMacroName}) {
        $sResult{ERROR}= "Recursion detected ('$sMacroName'). Ignored";
    }
    else {
        if (! defined $sMacro || ref $sMacro) {
            $sResult{ERROR}= "'$sMacroName' does not exist or is an object. Ignored.";
        }
        else {
            my $sMacro= $self->remove_backslashes_part1($sMacro);
            # build full macro name
            $sResult{MACRO}= $sMacroName;
            $hMacroStack->{$sMacroName}= 1;
            $sResult{DATA}= $self->_expand($sMacro, $hMacroStack);
            $hMacroStack->{$sMacroName} = 0;
        }
    }
    logger->error("Filter expansion: $sResult{ERROR}") if $sResult{ERROR};
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
    my $hMacroStack= shift || {};
    
    return () unless defined $sBaseDir;
    
    $sBaseDir=~ s/\/?$/\//;
    my $sqBaseDir= quotemeta $sBaseDir;

    $sFilter= $self->_expand($sFilter, $hMacroStack);
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

sub sort_show_key_order {
    my $self= shift;
    ($self->SUPER::sort_show_key_order(), "exclude", "include", "filter", "mount");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    $self->SUPER::show($hConfShowCache);
    
    my $hMacroStack= {};
    
    my @sFilter= $self->_get_filter($hMacroStack);
    print "# Referenced filters:\n" if scalar @sFilter;
    for my $sMacroName (sort keys %$hMacroStack) {
        my $sMacro= $self->get_raw_value("/$sMacroName");
        $sMacro=~ s/\n/\n\t/g;
        print "$sMacroName = $sMacro\n" unless defined $hConfShowCache->{$sMacroName};
        $hConfShowCache->{$sMacroName}= 1;
    }
    
    return unless $self->get_switch("logging") >= LOG_DEBUG_LEVEL;

    my $sBaseDir= $self->valid_source_dir();
    print "# Expanded rsync filter (relative to '$sBaseDir'):\n#\t" . join("\n#\t", @sFilter) . "\n";
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

    my @sFilter= $self->_get_filter();
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

    my $sFlags= "-a"
        . " --hard-links"
        . " --filter=\". $sRulesFile\""
        . " --stats"
        . " --verbose"
    ;

    $sFlags .= " -i" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $bPretend;
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;
    my $oSshPeer;
    if ($oTargetPath->is_remote()) {
        $oSshPeer= $oTargetPath;
    }
    elsif ($self->is_remote()) {
        $oSshPeer= $self;
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
        map { $sSshCmd.= " -i \"$_\"" if $_; } @sIdentityFiles if @sIdentityFiles;
        if ($oSshPeer->get_value("protocol")) {
            $sSshCmd.= " -1" if $oSshPeer->get_value("protocol") eq "1";
            $sSshCmd.= " -2" if $oSshPeer->get_value("protocol") eq "2";
        }
        $sFlags .= " -e '$sSshCmd' --timeout='$sTimeout'";
        $sFlags .= " --bwlimit='$sBandwidth'" if $sBandwidth;
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    my $sSrcDir = $self->getPath;

    # make sure path ends with "/"
    $sSrcDir=~ s/\/?$/\//;

    my $sDestDir= $oTargetPath->getPath($sFullTarget);
    # run rsync command on source by default

    my $oRsyncPath= $self;
    if ($oTargetPath->is_remote()) {
        $sDestDir= $oTargetPath->get_value("host") . ":$sDestDir";
        $sDestDir= $oTargetPath->get_value("user") . "\@$sDestDir" if $oTargetPath->get_value("user");
    }
    elsif ($self->is_remote()) {
        $sSrcDir= $self->get_value("host") . ":$sSrcDir";
        $sSrcDir= $self->get_value("user") . "\@$sSrcDir" if $self->get_value("user");
        $oRsyncPath= $oTargetPath;
    }

    my $sRsyncCmd= "rsync $sFlags \"$sSrcDir\" \"$sDestDir\"";

    logger->info("Running: $sRsyncCmd");

    # run rsync command
    my $sStdOutStat= 0;
    my %Handles= (
        STDOUT => sub {
            for my $sLine (split(/\n/, join("", @_))) {
                chomp $sLine;
                # skip directory lines
                next if $sLine =~ /^([^\/]+\/)+$/;
                if ($sLine =~ /^Number of .*\:\s+\d+$/) {
                    logger->info('*** Rsync Statistics: ***') unless $sStdOutStat;
                    $sStdOutStat= 1;
                }
                if ($sStdOutStat) {
                    logger->info($sLine);
                }
                else {
                    logger->verbose($sLine);
                }
            } 
        },
        STDERR => sub {logger->error(@_)},
    );
    my ($sRsyncOut, $sRsyncErr, $iRsyncExit, $sError)= $oRsyncPath->run_cmd($sRsyncCmd, \%Handles);
    logger->error($sError) if $sError;
    logger->warn("rsync exited with result ".  $iRsyncExit) if $iRsyncExit;

    # return success for partial transfer errors (errors were logged already above)
    return 0 if $iRsyncExit == 23 || $iRsyncExit == 24;
    return $iRsyncExit;
}

1;

