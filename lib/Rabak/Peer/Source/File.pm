#!/usr/bin/perl

package Rabak::Peer::Source::File;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(Rabak::Peer::Source);

use Data::Dumper;
use File::Spec;
use Rabak::Log;
use Rabak::Mountable;

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{MOUNTABLE}= Rabak::Mountable->new($self);
    
    return $self;
}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return (shift->SUPER::PropertyNames(), Rabak::Mountable->PropertyNames(), 'filter', 'exclude', 'include', 'scan_bak_dirs');
}

sub mountable {
    my $self= shift;
    return $self->{MOUNTABLE};
}

# hash table for detecting references and list of all used macros in filter expansion
sub _get_filter {
    my $self= shift;
    my $aMacroStack= shift || [];
    my $oTargetPeer= shift;

    my $sFilter= $self->get_raw_value('filter'); 
    
    # target path is always excluded
    my $aFilter= [];
    if ($oTargetPeer && $oTargetPeer->getUserHostPort() eq $self->getUserHostPort()) {
        push @$aFilter, "-" . $oTargetPeer->getPath() . "/";
    }
    if (defined $sFilter) {
        push @$aFilter, "&filter";
    }
    else {
        push @$aFilter, "-(", "&exclude", ")" if defined $self->get_raw_value('exclude');
        push @$aFilter, "+(", "&include", ")", "-/" if defined $self->get_raw_value('include');
    }

    return $self->_parseFilter($aFilter, $self->getPath(), $aMacroStack);
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
        
        # pathes starting with "./" are relative to $sBasePath
        $sEntry=~ s/^\.\//$sBaseDir/;

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

        if ($isDir && $sEntry=~ /^\//) {
            my $sqEntry= quotemeta $sEntry;
            # if $sEntry contains $sBaseDir use $sBaseDir instead
            if ($sBaseDir=~ /^$sqEntry./) {
                my $sMsg= "Directory '$sEntry' contains source path '$sBaseDir'. Using source path instead.";
                logger->debug($sMsg);
                push @sResult, "# Notice: $sMsg";
                $sEntry= $sBaseDir;
            }
        }
        if ($sEntry=~ /^\// && $sEntry!~ s/^$sqBaseDir/\//) {
            # cut entry on first occurance of '*'. '?' or '['
            if ($sEntry =~ /^(.+?)[\*\?\[]/) {
                my $sShortEntry= $1;
                my $sShortBase= substr($sBaseDir, 0, length $sShortEntry);
                logger->warn("Could not determine if '$sEntry' is contained in source path '$sBaseDir'. Ignored.") if $sShortBase eq $sShortEntry;
            }
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
            my $hMacro= $self->expandMacroHash($sEntry, $oScope, $aMacroStack,
                sub {$self->_expand(@_)}, # function to expand macro's content
                sub{ # function to modify macro's text before splitting
                    my $sEntry= shift;
                    my $sregIdent= $self->REGIDENTREF;
                    # remove spaces between +/- and path, a +/- always separates
                    $sEntry=~ s/(?<!\\)\s*(?<!\\)([\-\+])\s+/ $1/g;
                    # enclose all macros &... with parantheses
                    $sEntry=~ s/(?<!\\)(\&$sregIdent)/\($1\)/g;
                    # enclose all macros &{..} with parantheses
                    $sEntry=~ s/(?<!\\)\&\{($sregIdent)\}/\(\&$1\)/g;
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
            logger->error("Internal Error(2) (List Expected)") unless $hEntries->{TYPE} eq 'list';
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

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    my $oTarget= shift;

    # overwrite Source's SUPER class with Mountable
    my $aResult = $self->SUPER::show($hConfShowCache);
    push @$aResult, @{$self->mountable()->show($hConfShowCache)};
    
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
    
    return $aResult unless $self->get_switch("show_filter", 0);

    my $sBaseDir= $self->getFullPath();
    push @$aResult, "", "# Expanded rsync filter (relative to '$sBaseDir'):", map {"#\t$_"} @sFilter;
    return $aResult;
}

sub valid_source_dir {
    my $self= shift;

    my $sSourceDir= $self->getFullPath();

    unless ($self->isDir()) {
        logger->error("Source \"$sSourceDir\" is not a directory. Backup set skipped.");
        return undef;
    }
    unless ($self->isReadable()) {
        logger->error("Source \"$sSourceDir\" is not readable. Backup set skipped.");
        return undef;
    }

    return $self->getPath();
}

sub _run_rsync {
    my $self = shift;
    my $oRsyncPeer = shift || $self;
    my $sSrc = shift or die "_run_rsync: No source specified";
    my $sDst = shift or die "_run_rsync: No target specified";
    my $sFlags = shift || '';
    my $hHandles = shift || {};
    
    $sSrc =  $self->ShellQuote($sSrc);
    $sDst =  $self->ShellQuote($sDst);
    my $sRsyncCmd= "rsync $sFlags $sSrc $sDst";

    logger->info("Running" .
        ($oRsyncPeer->is_remote() ?
            " on '" . $oRsyncPeer->getUserHostPort() . "'" :
            "") .
        ": $sRsyncCmd");
    logger->incIndent();

    # run rsync command
    my (undef, undef, $iExit, $sError)= $oRsyncPeer->run_cmd($sRsyncCmd, $hHandles);

    logger->decIndent();
    logger->error($sError) if $sError;
    if ($iExit) {
        logger->warn("rsync exited with result $iExit");
        return $iExit;
    }
    logger->info("rsync finished successfully");
    return 0;    
}

sub prepareBackup {
    my $self= shift;
    
    $self->SUPER::prepareBackup();
    
    my @sMountMessage;
    my $iMountResult= $self->mountable()->mountAll(\@sMountMessage);

    logger->log(@sMountMessage);

    return $self->valid_source_dir() ? 0 : 1;
}

sub finishBackup {
    my $self= shift;
    
    $self->mountable()->unmountAll();

    $self->SUPER::finishBackup();
    return 0;
}

sub checkMount {
    my $self= shift;
    my $sMountDevice= shift;
    my $arMountMessages= shift;

    return $self->mountable()->checkMount($sMountDevice, $arMountMessages);
}

sub mountErrorIsFatal {
    my $self= shift;
    my $iMountResult= shift;

    return 0;
}

sub run {
    my $self= shift;
    my $oTargetPeer= shift;
    my $hMetaInfo= shift;

    # print Dumper($self); die;

    # print '**$bPretend**'; die;

    # Unused: my $sBakSet= $self->get_value('name');

    my @sRsyncOpts = $self->resolveObjects('rsync_opts') || ();

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->local_tempfile();

    my @sFilter= $self->_get_filter(undef, $oTargetPeer);
    # print join("\n", @sFilter), "\n"; #die;

    print $fhwRules join("\n", @sFilter), "\n";
    close $fhwRules;

    # copy filter rules to source if target AND source are remote
    if ($oTargetPeer->is_remote() && $self->is_remote()) {
        my $sRemRulesFile= $self->tempfile;
        $self->copyLocalFileToRemote($sRulesFile, $sRemRulesFile);
        $sRulesFile = $sRemRulesFile;
    }

    # print `cat $sRulesFile`;

    my @sFlags= (
        '--archive', 
        '--sparse',
        '--hard-links',
        '--filter=. ' . $sRulesFile,
        '--stats',
        '--verbose',
        '--verbose',
        '--itemize-changes',
        '--itemize-changes',
    );

    push @sFlags, '--dry-run' if $self->pretend();
    push @sFlags, @sRsyncOpts;
    
    # $oSshPeer contains ssh parameters for rsync (seen from executing location)
    # - is TargetPeer if target is remote (rsync will be run on SourcePeer)
    # - is SourcePeer if target is local and source is remote (rsync will be run locally)
    # $oRsyncPeer contains peer rsync is running from
    # - is TargetPeer if target is local and source is remote
    # - is SourcePeer otherwise
    my $oSshPeer;
    my $oRsyncPeer = $self;
    my $sSourceDirPref = "";
    my $sTargetDirPref = "";
    if ($oTargetPeer->is_remote()) {
        # unless target and source on same host/user/port
        unless ($oTargetPeer->getUserHostPort() eq $self->getUserHostPort()) {
            $oSshPeer = $oTargetPeer;
            $sTargetDirPref= $oTargetPeer->getUserHost(":");
        }
    }
    elsif ($self->is_remote()) {
        $oSshPeer= $self;
        $sSourceDirPref= $self->getUserHost(":");
        $oRsyncPeer = $oTargetPeer;
    }
    if ($oSshPeer) {
        my $sPort= $oSshPeer->get_value("port") || 22;
        my $sTimeout= $oSshPeer->get_value("timeout") || 150;
        my $sBandwidth= $oSshPeer->get_value("bandwidth") || '';
        my @sIdentityFiles= $oSshPeer->get_value("identity_files") ? split(/\s+/, $oSshPeer->get_value("identity_files")) : undef;

        if (grep {/^\-\-bwlimit\=(\d+)/} @sRsyncOpts) {
            $sBandwidth= $1 unless $sBandwidth;
            @sRsyncOpts= grep {!/^\-\-bwlimit\=\d+/} @sRsyncOpts;
            logger->warn("--bandwidth in 'rsync_opts' is deprecated. Please use 'bandwidth' option (see Doc)!");
        }
        if (grep {/^\-\-timeout\=(\d+)/} @sRsyncOpts) {
            $sTimeout= $1 unless $oTargetPeer->get_value("timeout");
            @sRsyncOpts= grep {!/^\-\-timeout\=\d+/} @sRsyncOpts;
            logger->warn("--timeout in 'rsync_opts' is deprecated. Please use 'timeout' option (see Doc)!");
        }

        my @sSshCmd= (
            'ssh',
            '-p', $sPort,
        );
        my $sSshCmd= "ssh -p $sPort";
        push @sSshCmd, map { ('-i', $_) } grep {$_} @sIdentityFiles;
        if ($oSshPeer->get_value("protocol")) {
            push @sSshCmd, '-1' if $oSshPeer->get_value('protocol') eq '1';
            push @sSshCmd, '-2' if $oSshPeer->get_value('protocol') eq '2';
        }
        push @sFlags, '--rsh=' . $self->ShellQuote(@sSshCmd), "--timeout=$sTimeout", '--compress';
        push @sFlags, "--bwlimit=$sBandwidth" if $sBandwidth;
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    my @sBakDir= @{$hMetaInfo->{OLD_DATA_DIRS}};
    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    push @sFlags, map {'--link-dest=' . $_} @sBakDir;

    my $sSourceDir = $self->getPath;

    # make sure path ends with "/"
    $sSourceDir=~ s/\/?$/\//;

    # prepare handles for stdout/stderr
    my $sStdOutStat= 0;
    my @sLinkErrors= ();
    my $sTargetDir= $hMetaInfo->{DATA_DIR};
    my $sqTargetDir= quotemeta $sTargetDir;
    my $fHandleHardLinksTo= sub{
        my $sFile= shift;
        my $sLink= shift;
#        logger->verbose("Linking file \"$sFile\" to \"$sLink\"");
    };
    my $fHandleHardLinksToPrev= sub{
        my $sFile= shift;
#        logger->verbose("Linking file \"$sFile\" to a previous version")
    };
    my $fHandleChangedFile= sub{
        my $sFile= shift;
        logger->verbose("backed up \"$sFile\"")
    };
    my %Handles= (
        STDOUT => sub {
            for my $sLine (@_) {
                chomp $sLine;
                # detect some warnings
                if ($sLine =~ /^file has vanished\: \".*\"$/) {
                    logger->warn($sLine);
                    next;
                }
                if ($sLine =~ /^total\:/) {
                    $sStdOutStat= 1;
                }
                if ($sLine =~ /^Number of .*\:\s+\d+$/) {
                    logger->info('*** Rsync Statistics: ***') unless $sStdOutStat == 2;
                    $sStdOutStat= 2;
                }
                next if $sStdOutStat == 1;
                unless ($sStdOutStat) {
                    # skip directory lines
                    next if $sLine =~ /^cd/;
                    if ($sLine =~ /^\[sender\] hiding/) {
                    	next;
                    }
                    if ($sLine =~ /^([\>\<ch\.\*][fdLDS][ \.\+\?cstpoguax]{9})\s(.+)$/) {
                        my ($flags, $sFile) = ($1, $2);
                        next if $sFile eq './';
                        # skip symlinks
                        next if $flags=~ /^.L/;
                        $hMetaInfo->{FILE_CALLBACK}->("$sTargetDir/$sFile") if $hMetaInfo->{FILE_CALLBACK};
                        if ($flags=~ /^h/) {
                            if ($sFile =~ s/ \=\> (.+)$//) {
                                $fHandleHardLinksTo->($sFile, $1);
                            }
                            else {
                                $fHandleHardLinksToPrev->($sFile);
                            }
                        }
                        else {
                            $fHandleChangedFile->($sFile);
                        }
                        next;
                    }
                }
                logger->info($sLine);
            } 
        },
        STDERR => sub {
            for my $sLine (@_) {
                chomp $sLine;
                if ($sLine =~ /^rsync\: link \"$sqTargetDir\/(.+)\" \=\> .+ failed\: Too many links/) {
                    push @sLinkErrors, $1;
                    logger->verbose($sLine);
                    next;
                }
                logger->error(@_);
            }
        },
    );

    # run rsync cmd
    my $iRsyncExit = $self->_run_rsync($oRsyncPeer, $sSourceDirPref.$sSourceDir, $sTargetDirPref.$sTargetDir, scalar $self->ShellQuote(@sFlags), \%Handles);

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
        if ($oRsyncPeer->is_remote()) {
            my $sRemFilesFile= $oRsyncPeer->tempfile;
            $oRsyncPeer->copyLocalFileToRemote($sFilesFile, $sRemFilesFile);
            $sFilesFile = $sRemFilesFile;
        }
        # reset StdOut flag for STDOUT handler
        $sStdOutStat= 0;
        # simple error handling only
        $Handles{STDERR} = sub {logger->error(@_)};

        # run rsync cmd (drop exit code - has been logged anyway)
        $self->_run_rsync(
            $oRsyncPeer, $sSourceDirPref.$sSourceDir, $sTargetDirPref.$sTargetDir,
            scalar $self->ShellQuote(@sFlags, "--files-from=$sFilesFile"),
            \%Handles
        );

        logger->decIndent();
        logger->info("...done fixing hard link errors.");
    }

    # return success for partial transfer errors (errors were logged already above)
    return 0 if $iRsyncExit == 23 || $iRsyncExit == 24;
    return $iRsyncExit;
}

sub getPath {
    my $self= shift;
    return $self->mountable()->getPath(@_);
}

1;

