#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;

use RabakLib::Log;
use RabakLib::Path;
use RabakLib::Path::Source;
use RabakLib::Path::Target;

use Data::Dumper;
use File::Spec ();
use Mail::Send;
use POSIX qw(strftime);

# use URI;

use vars qw(@ISA);

@ISA = qw(RabakLib::Conf);

sub new {
    my $class= shift;
    my $hConf= shift || {};
    my $sName= lc(shift || '');
    my $bSkipValidation= shift;

    my $self;
    # print Dumper($sName); die;
    if ($sName && defined $hConf->{VALUES}{$sName}) {
        $self= $class->SUPER::new($hConf->{VALUES}{$sName});
        $self->{ERROR}= $bSkipValidation ? undef : $self->_validate();
    }
    else {
        $self= $class->SUPER::new();
        $self->{ERROR}= "No set \"$sName\" defined";
        $bSkipValidation= 1;
    }
    $self->{ERRORCODE}= 0;
    $self->{DEBUG}= 0;
    $self->{CONF}= $hConf;
    $self->{VERSION}= $hConf->{DEFAULTS}->{VERSION};
    $self->{NAME}= $sName;

    $self->{_TARGET_OBJECT}= undef;

    logger->init($hConf);

    logger->set_category($sName);

    # my $xx= "file://C:/etc/passwd";
    # my $uri= URI->new($xx); # self->{VALUES}{source});
    # print Dumper($uri);

    # print "\n" . $uri->scheme;
    # print "\n" . $uri->opaque;
    # print "\n" . $uri->path;
    # print "\n" . $uri->fragment;
    # exit;

#    if (defined $self->{VALUES}{source} && !ref $self->{VALUES}{source} && $self->{VALUES}{source} =~ /^([a-z]+):(.*)/) {
#        $self->{VALUES}{type}= $1;
#        $self->{VALUES}{source}= $2;
#    }
#    else {
#        $self->{VALUES}{type}= 'file' unless defined $self->{VALUES}{type} || ref $self->{VALUES}{type};
#    }

    unless ($bSkipValidation) {
        $self->{ERROR}= $self->_validate();

        # TODO: fix (should be moved to SourcePath??)
        # if ($self->{VALUES}{type} !~ /^(file|pgsql|mysql)$/) {
        #     return "Backup set type of \"$sName.source\" must be \"file\", \"pgsql\" or \"mysql\". (" . $self->{VALUES}{source} . ")";
        # }
    }
    $self->set_value("name", $sName);

    bless $self, $class;
}

sub _need_value {
    my $self= shift;
    my $sField= shift;

    return "Required value \"" . $self->get_value("name") . ".$sField\" missing." unless defined $self->{VALUES}{$sField};
    return undef;
}

sub _validate {
    my $self= shift;

    return $self->_need_value('title') || $self->_need_value('source') || $self->_need_value('target');
}

sub show {
    my $self= shift;
    my $sKey= shift || $self->{NAME};

    $self->SUPER::show($sKey);

    my $sType= $self->get_value("type");

    my @oSources= $self->get_sourcePaths();

    my $oTarget= $self->get_targetPath();
    print "\nEffective target: " . $oTarget->getFullPath() . "\n";
    print "\nEffective sources: \n";

    for my $oSource (@oSources) {
        print ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n";# unless $oSource == $oSources[0];

        $oSource->show();
    }
    print "$@\n" if $@;
    print "\n\n";
}

# =============================================================================
#  Generate Output for dot (graphviz)
#  TODO: This does not belong into Set.pm (too much overhead)
# =============================================================================

our %_boxAdded;

sub dotify {
    $_[0] =~ s/"/\\"/g;
    return $_[0];
}

sub dothtmlify {
    $_[0] =~ s/&/&amp;/g;
    $_[0] =~ s/</&lt;/g;
    $_[0] =~ s/>/&gt;/g;
    return $_[0];
}

sub _dotAddBox {
    my $self= shift;
    my $sType= shift;
    my $oConf= shift;
    my $oParentConf= shift;

    my $sTitleBgColor= '#DDDDDD';
    $sTitleBgColor= '#DDDD00' if $sType eq 'mount';
    $sTitleBgColor= '#00DDDD' if $sType eq 'source';
    $sTitleBgColor= '#DD00DD' if $sType eq 'target';

    my $sAttribs= 'shape="rect"';
    $sAttribs= 'shape="polygon" skew="0.5"' if $sType eq 'mount';
    $sAttribs= 'shape="invhouse"' if $sType eq 'mount';
    $sAttribs= 'shape="rect" style="filled" color="#F0F0E0"' if $sType eq 'mount';

    my $sName= $oConf->{NAME};
    my $sTitleText= $oConf->{VALUES}{'name'} || $sName;
    $sTitleText= ucfirst($sType) . " \"$sTitleText\"";

    $sTitleText= dothtmlify($sTitleText);
    $sTitleText= "<table border=\"0\"><tr><td>$sTitleText</td></tr></table>";

    my $sResult= '';
    $sResult .= "$sName [ label=<";
    $sResult .= "<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\">";
    $sResult .= "<tr><td colspan=\"3\" bgcolor=\"$sTitleBgColor\">$sTitleText</td></tr>";
    $sResult .= "<tr><td colspan=\"3\"><font point-size=\"4\">&#160;</font></td></tr>";
    for my $sKey (sort keys %{ $oConf->{VALUES} }) {
        my $sValue= $oConf->{VALUES}{$sKey} || '';
        next if $sValue eq '';
        $sValue= substr($sValue, 0, 27) . "..." if length($sValue) > 30;
        $sResult .= "<tr><td align=\"left\">" . dothtmlify($sKey) . ":</td><td>&#160;</td><td align=\"left\">" . dothtmlify($sValue) . "</td></tr>";
        # print Dumper($oSource->{VALUES});
    }
    $sResult .= "</table>";
    $sResult .= "> $sAttribs ]\n";

    $sResult= "" if $_boxAdded{$sName};

    $_boxAdded{$sName}= 1;

    if ($oParentConf) {
        my $sParentName= $oParentConf->{NAME};
        if ($sType eq 'target') {
            $sResult .= "$sParentName -> $sName\n";
        }
        else {
            $sResult .= "$sName -> $sParentName\n";
        }
    }
    return $sResult;
}

# Build output as graphviz directed graph
#
sub toDot {
    my $self= shift;

    %_boxAdded= ();

    # print "]\n[";
    # print $self->get_value("name");
    # print "]\n[";
    # print $self->get_value("title");
    # print "]\n[";

    my @oSources= $self->get_sourcePaths();

    my $sResult= '';

    $sResult .= $self->_dotAddBox('set', $self);

    for my $oSource (@oSources) {
        $sResult .= $self->_dotAddBox('source', $oSource, $self);
    }

    my $oTarget= $self->get_targetPath();
    $sResult .= $self->_dotAddBox('target', $oTarget, $self);

    my $sTitle= "Set \"" . ($self->{VALUES}{'name'} || $self->{NAME}) . "\"";

    $sResult= qq(
        subgraph cluster1 {
            label=" ) . dotify($sTitle) . qq( "
            labelfontsize="18"
            $sResult
        }
    ) if 1;

    for my $oSource (@oSources) {
        for my $oMount ($oSource->getMountObjects()) {
            $sResult .= $self->_dotAddBox('mount', $oMount, $oSource);
        }
    }

    for my $oMount ($oTarget->getMountObjects()) {
        $sResult .= $self->_dotAddBox('mount', $oMount, $oTarget);
    }

    $sResult= qq(
        digraph {
            // rankdir="LR"
            $self->{NAME} [ shape="rect" ]
            $sResult
        }
    );

    return $sResult;
}

# =============================================================================
#  ...
# =============================================================================

sub get_raw_value {
    my $self= shift;
    my $sName= shift || '';
    my $sDefault= shift;

    my $sResult= $self->SUPER::get_raw_value($sName);
    return  $sResult;
}

sub get_global_raw_value {
    my $self= shift;
    my $sName= shift || '';
    my $sDefault= shift;

    my $sResult= $self->get_raw_value($sName);
    $sResult= $self->{CONF}->get_raw_value($sName) unless defined $sResult;
    return  $sResult;
}

sub get_global_value {
    my $self= shift;
    my $sName= shift || '';
    my $sDefault= shift;

    return  $self->remove_backslashes_part2($self->remove_backslashes_part1($self->get_global_raw_value($sName, $sDefault)));
}

sub get_global_node {
    my $self= shift;
    my $sName= shift || '';

    my $hResult= $self->SUPER::get_node($sName);
    $hResult= $self->{CONF}->get_node($sName) unless defined $hResult;
    return  $hResult;
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub _timestr {
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

sub logPretending {
    my $self= shift;
    return unless $self->get_global_value('switch.pretend');

    logger->log("", "*** Only pretending, no changes are made! ****", "");
}

sub _mail {
    my $self= shift;
    my ($sSubject, @aBody) = @_;
    
    my $sMailAddress= $self->get_global_value('email'); 

    return 0 unless $sMailAddress;

    my $oMail = new Mail::Send Subject => $sSubject, To => $sMailAddress;
    # $msg->cc('user@host');
    my $fh = $oMail->open;
    print $fh join("\n", @aBody);
    $fh->close;

    return 1;
}

sub _mail_log {
    my $self= shift;
    my $sSubject= shift;

    my $iErrors= logger->get_errorCount;
    my $iWarns= logger->get_warnCount;
    my $sErrWarn;
    $sErrWarn= "$iErrors error" if $iErrors; 
    $sErrWarn.= "s" if $iErrors > 1; 
    $sErrWarn.= ", " if $iErrors && $iWarns; 
    $sErrWarn.= "$iWarns warning" if $iWarns; 
    $sErrWarn.= "s" if $iWarns > 1; 
    $sSubject.= " ($sErrWarn)" if $sErrWarn;
    
    $sSubject= "RABAK '" . $self->get_value("name") . "': $sSubject";
    return $self->_mail($sSubject, logger->get_messages());
}

sub _mail_warning {
    my $self= shift;
    my ($sSubject, @aBody) = @_;

    return $self->_mail("RABAK WARNING: $sSubject", @aBody);
}

# -----------------------------------------------------------------------------
#  ...
# -----------------------------------------------------------------------------

sub get_targetPath {
    my $self= shift;

    $self->{_TARGET_OBJECT}= RabakLib::Path::Target->new($self) unless $self->{_TARGET_OBJECT};
    return $self->{_TARGET_OBJECT};
}

# collect all backup dirs
sub collect_bakdirs {
    my $self= shift;
    my $sqBakSet= quotemeta shift;
    my $sqBakSource= shift;
    my $sSubSetBakDay= shift || 0;

    $sqBakSource= "(" . quotemeta(".$sqBakSource") . ")|" if $sqBakSource;
    my $oTargetPath= $self->get_targetPath();
    my @sBakDir= ();
    my $sSubSet= '';

    my %hBakDirs = $oTargetPath->getDirRecursive('', 1); # get recurisive file listing for 2 levels
    for my $sMonthDir (keys %hBakDirs) {
        next unless ref $hBakDirs{$sMonthDir}; # dirs point to hashes

        next unless $sMonthDir =~ /\/(\d\d\d\d\-\d\d)\.($sqBakSet)$/;

        for my $sDayDir (keys %{$hBakDirs{$sMonthDir}}) {
            next unless ref $hBakDirs{$sMonthDir}->{$sDayDir}; # dirs point to hashes
            # print "$sDayDir??\n";
            next unless $sDayDir =~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?($sqBakSource(\.$sqBakSet))$/; # [a-z] for backward compatibility
            if ($sSubSetBakDay eq $1) {
                my $sCurSubSet= $2 || '';
                die "Maximum of 1000 backups reached!" if $sCurSubSet eq '_999';
                if (!$sCurSubSet) {
                    $sSubSet= '_001' if $sSubSet eq '';
                }
                elsif ($sSubSet le $sCurSubSet) {
                    $sCurSubSet=~ s/^[\-_]0*//;
                    $sSubSet= sprintf("_%03d", $sCurSubSet + 1);
                }
            }
            push @sBakDir, $sDayDir;
            # print "$sDayDir\n";
        }
    }

    @sBakDir= sort { $b cmp $a } @sBakDir;

    unshift @sBakDir, $sSubSet if $sSubSetBakDay;

    return @sBakDir;
}

# -----------------------------------------------------------------------------
#  Little Helpers
# -----------------------------------------------------------------------------

sub _mkdir {
    my $self= shift;
    my $sDir= shift;

    return 1 if $self->get_global_value('switch.pretend');

    # TODO: set MASK ?
    # return 1 if $self->{_TARGET_OBJECT}->mkdir($sDir);

    return 1 if $self->get_targetPath()->mkdir($sDir);

    logger->warn("Mkdir '$sDir' failed: $!");
    return 0;
}

sub _build_bakMonthDay {
    my $self= shift;
    return (strftime("%Y-%m", localtime), strftime("%Y-%m-%d", localtime));
    
}

# -----------------------------------------------------------------------------
#  Backup
# -----------------------------------------------------------------------------

sub get_sourcePaths {
    my $self= shift;
    
    my @oSources= ();
    my $sSources= $self->remove_backslashes_part1($self->get_raw_value("source"));
    my @sSources= ( "&source" );
    if ($sSources) {
        my @aRawSources= split /(?<!\\)\s+/, $sSources;
        @sSources= map $self->remove_backslashes_part2($_), @aRawSources;
    }
    for my $sSource (@sSources) {
        my $oSource = RabakLib::Path::Source->Factory($self, $sSource);
        if ($oSource) {
            push @oSources, $oSource;
        }
        else {
            logger->error("Source Object '$sSource' could not be loaded. Skipped.");
        }
        
    } 
    return @oSources;
}

sub backup {
    my $self= shift;

    my $iSuccessCount= 0;
    my $iResult= 0; 
    
    my @oSources= $self->get_sourcePaths();

    # mount all target mount objects
    my @sMountMessage= ();
    my $oTargetPath= $self->get_targetPath();
    my $iMountResult= $oTargetPath->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        logger->error("There was at least one fatal mount error on target. Backup set skipped.");
        logger->error(@sMountMessage);
        $iResult= -3;
        goto cleanup;
    }
    logger->log(@sMountMessage);

    # check target dir
    unless ($oTargetPath->isDir) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$oTargetPath->get_value("path")."\" is not a directory. Backup set skipped.");
        $iResult= -1;
        goto cleanup;
    }
    unless ($oTargetPath->isWritable) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$oTargetPath->get_value("path")."\" is not writable. Backup set skipped.");
        $iResult= -2;
        goto cleanup;
    }

    my ($sBakMonth, $sBakDay)= $self->_build_bakMonthDay;
    my $sBakSet= $self->get_value("name");

    # create target month dir
    my $sTarget= "$sBakMonth.$sBakSet";
    $self->_mkdir($sTarget);

    # start logging
    my $sLogFile= "$sBakMonth-log/$sBakDay.$sBakSet.log";

    if (!$self->get_global_value('switch.pretend') && $self->get_global_value('switch.logging')) {
        $self->_mkdir("$sBakMonth-log");

        my $sLogLink= "$sBakMonth.$sBakSet/$sBakDay.$sBakSet.log";

        my $sLogFileName= $oTargetPath->get_value("PATH") . "/$sLogFile";

        my $sError= logger->open($sLogFileName, $oTargetPath);
        if ($sError) {
            logger->warn("Can't open log file \"$sLogFileName\" ($sError). Going on without...");
        }
        else {
            # TODO: transfer to Log.pm
            if (!logger->is_new()) {

                # TODO: only to file
                logger->log("", "===========================================================================", "");
            }
            $oTargetPath->symlink("../$sLogFile", "$sLogLink");
            $oTargetPath->unlink("current-log.$sBakSet");
            $oTargetPath->symlink($sLogFile, "current-log.$sBakSet");
        }
    }
    logger->log("Logging to: ".$oTargetPath->getFullPath."/$sLogFile") if $self->get_global_value('switch.logging');
    logger->info("Rabak Version " . $self->get_global_value("version"));
    $self->logPretending();

    # now try backing up every source 
    my %sNames= ();
    for my $oSource (@oSources) {
        my $sName= $oSource->get_value("name") || '';
        if ($sNames{$sName}) {
            logger->error("Name '$sName' of Source Object has already been used. Skipping backup of source.");
            next;
        }
        $sNames{$sName}= 1;
        eval {
            if ($self->_backup_setup($oSource) == 0) {
                $iSuccessCount++ unless $self->_backup_run($oSource);
            }
            $self->_backup_cleanup($oSource);
        };
        logger->log(logger->error("An error occured during backup: '$@'")) if $@;
    }

    # stop logging
    logger->close();
    
    $iResult= scalar(@oSources) - $iSuccessCount;

cleanup:
    # unmount all target mounts
    $oTargetPath->unmountAll;

    my $sSubject= "successfully finished";
    $sSubject= "$iSuccessCount of " . scalar(@oSources) . " backups $sSubject" if $iResult;
    $sSubject= "*PRETENDED* $sSubject" if $self->get_global_value("switch.pretend");

    # send admin mail
    $self->_mail_log($sSubject);
    
    # return number of failed backups or error code (negative)
    return $iResult;
}

sub _backup_setup {
    my $self= shift;
    my $oSource= shift;

    my $sSubSet= "";
    my @sBakDir= ();
    my $oTargetPath= $self->get_targetPath();

    my @sMountMessage;
    my $iMountResult= $oSource->mountAll(\@sMountMessage);

    # mount errors on source are non-fatal!
    #unless ($iMountResult) { # fatal mount error
    #    logger->error("There was at least one fatal mount error on source. Backup set skipped.");
    #    logger->error(@sMountMessage);
    #    return 3;
    #}

    logger->log(@sMountMessage);

    my ($sBakMonth, $sBakDay)= $self->_build_bakMonthDay;
    my $sBakSet= $self->get_value("name");
    my $sBakSource= $oSource->get_value("name") || '';

    ($sSubSet, @sBakDir)= $self->collect_bakdirs($sBakSet, $sBakSource, $sBakDay);

    my $sUniqueTarget= "$sBakDay$sSubSet";
    $sUniqueTarget.= ".$sBakSource" if $sBakSource;
    $self->set_value("unique_target", $sUniqueTarget);
    my $sTarget= "$sBakMonth.$sBakSet/$sUniqueTarget";
    $self->set_value("full_target", $oTargetPath->getPath . "/$sTarget");

    $self->_mkdir($sTarget);

    logger->info("Backup $sBakDay exists, using subset.") if $sSubSet;
    logger->info("Backup start at " . strftime("%F %X", localtime) . ": $sBakSource, $sBakDay$sSubSet, " . $self->get_value("title"));
    logger->log("Source: " . $oSource->getFullPath);

    $self->{_BAK_DIR_LIST}= \@sBakDir;
    $self->{_BAK_DAY}= $sBakDay;
    $self->{_SUB_SET}= $sSubSet;
    $self->{_TARGET}= $sTarget;

    return 0;
}

sub _backup_run {
    my $self= shift;
    my $oSource= shift;

    my $sBakType= $self->get_value("type");

    my @sBakDir= @{ $self->{_BAK_DIR_LIST} };
    my $oTargetPath= $self->get_targetPath;
    my $sBakSetSource= $self->get_value("name");
    $sBakSetSource.= "-" . $oSource->get_value("name") if $oSource->get_value("name");
    my $sTarget= $self->{_TARGET};

    my $iErrorCode= 0;
    logger->set_prefix($sBakType);
    $iErrorCode= $oSource->run($oTargetPath, $self->get_value("full_target"), $self->get_value("unique_target"), @sBakDir);
    logger->set_prefix();

    if (!$iErrorCode) {
        logger->log("Done!");
    }
    else {
        logger->error("Backup failed: " . $oSource->get_last_error);
        $iErrorCode= 9;
    }

    # for backward compatiblity use only dir with source name (not set name like for file linking) 
    my @sKeepDirs= ();
    my $sqBakSource='';
    $sqBakSource= quotemeta("." . $oSource->get_value("name")) if $oSource->get_value("name");
    for my $sBakDir (@sBakDir) {
        push @sKeepDirs, $sBakDir if $sBakDir=~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?$sqBakSource$/;
    }
    $oTargetPath->remove_old($oSource->get_value("keep"), @sKeepDirs) unless $iErrorCode;    # only remove old if backup was done

    unless ($self->get_global_value('switch.pretend')) {
        $oTargetPath->unlink("current.$sBakSetSource");
        $oTargetPath->symlink("$sTarget", "current.$sBakSetSource");
    }

    # check for disc space
    # TODO: Transfer to Path::Target
    my $sSpaceThreshold= $oTargetPath->get_value('discfree_threshold') || '';
    if ($sSpaceThreshold) {
        my $iStValue= $sSpaceThreshold =~ /\b([\d\.]+)/ ? $1 : 0;
        my $sStUnit= 'K';
        $sStUnit = uc($1) if $sSpaceThreshold =~ /$iStValue\s*([gmkb\%])/i;
        my $sDfResult = (split /\n/, $oTargetPath->df('', "-k"))[1];
        my ($iDfSize, $iDfAvail) = ($1, $2) if $sDfResult =~ /^\S+\s+(\d+)\s+\d+\s+(\d+)\s+/;
        $iDfAvail /= $iDfSize / 100 if $sStUnit eq '%';
        $iDfAvail >>= 20            if $sStUnit eq 'G';
        $iDfAvail >>= 10            if $sStUnit eq 'M';
        $iDfAvail <<= 10            if $sStUnit eq 'B';
        if ($iStValue > $iDfAvail) {
            $self->_mail_warning('disc space too low',
                (
                    "The free space on your target \"" .
                    $oTargetPath->getFullPath . "\" has dropped",
                    "below $iStValue$sStUnit to $iDfAvail$sStUnit."
                )
            );
        }
    }

    return $iErrorCode;
}

sub _backup_cleanup {
    my $self= shift;
    my $oSource= shift;

    $oSource->unmountAll;

    my $sBakSource= $oSource->get_value("name");
    my $sBakDay= $self->{_BAK_DAY};
    my $sSubSet= $self->{_SUB_SET};

    logger->info("Backup done at " . strftime("%F %X", localtime) . ": $sBakSource, $sBakDay$sSubSet") if $sBakSource && $sBakDay && $sSubSet;
}

# -----------------------------------------------------------------------------
#  Remove file
# -----------------------------------------------------------------------------

sub rm_file {

    die "The current rm_file is flawed. It will be available again in the next release!";

    my $self= shift;
    my @sFileMask= shift || ();
    my $oSource= shift; die "parameter has to be configured";

    # print Dumper(\@sFileMask);

    map { logger->logExitError(2, "Every filemask MUST start with \"/\"!") unless /^\//; } @sFileMask;

    return 2 unless scalar @sFileMask && defined $sFileMask[0];

    $self->logPretending();

    my %aDirs= ();
    my %aFiles= ();
    my %iFoundMask= ();

    my $sBakSet= $self->get_value("name");
    my $sBakSetDay= $sBakSet;
    $sBakSetDay.= "-" . $oSource->get_value("name") if $oSource->get_value("name");
    my $oTargetPath= $self->get_targetPath();

    # TODO: Make a better check!
    logger->logExitError(3, "Can't remove! \"$sBakSet.target\" is empty or points to file system root.") if $oTargetPath->getPath eq '' || $oTargetPath->getPath eq '/';

    my @sBakDir= $self->collect_bakdirs($sBakSet, $sBakSetDay);

    # print Dumper(\@sBakDir);

    foreach my $sBakDir (@sBakDir) {
        foreach my $sFileMask (@sFileMask) {
            while (<$sBakDir$sFileMask>) {
                my $sFound= $_;

                # print "**$sBakDir :: $sFileMask :: $_**\n";

                $sFound =~ s/^$sBakDir//;
                if (-d $_) {
                    $aDirs{$sFound}= () unless defined $aDirs{$sFound};
                    push @{ $aDirs{$sFound} }, $_;
                    $iFoundMask{$sFileMask}++;
                }
                elsif (-r _) {
                    $aFiles{$sFound}= () unless defined $aFiles{$sFound};
                    push @{ $aFiles{$sFound} }, $_;
                    $iFoundMask{$sFileMask}++;
                }
                else {
                    print "??: $_\n" if $self->{DEBUG};
                }
            }
        }
    }

    map {
        logger->log("Removing " . scalar @{ $aDirs{$_} } . " directories: $_");
        !$self->get_global_value('switch.pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        logger->log("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->get_global_value('switch.pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { logger->log("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
