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
        $self= $class->SUPER::new($sName, $hConf->{VALUES}{$sName});
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

    $self->set_log(RabakLib::Log->new($hConf));
    $self->get_log->set_category($sName);

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
        $oSource->_show();
    }
    print "$@\n" if $@;
    print "\n\n";
}

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

    $self->log("", "*** Only pretending, no changes are made! ****", "");
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

    my $iErrors= $self->get_log->get_errorCount;
    my $iWarns= $self->get_log->get_warnCount;
    my $sErrWarn;
    $sErrWarn= "$iErrors error" if $iErrors; 
    $sErrWarn.= "s" if $iErrors > 1; 
    $sErrWarn.= ", " if $iErrors && $iWarns; 
    $sErrWarn.= "$iWarns warning" if $iWarns; 
    $sErrWarn.= "s" if $iWarns > 1; 
    $sSubject.= " ($sErrWarn)" if $sErrWarn;
    
    $sSubject= "RABAK '" . $self->get_value("name") . "': $sSubject";
    return $self->_mail($sSubject, $self->get_log->get_messages());
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

    $self->{_objTarget}= RabakLib::Path::Target->new($self) unless $self->{_objTarget};
    return $self->{_objTarget};
}

# collect all backup dirs
sub collect_bakdirs {
    my $self= shift;
    my $sBakSet= quotemeta shift;
    my $sBakSource= quotemeta shift;
    my $sSubSetBakDay= shift || 0;

    my $oTargetPath= $self->get_targetPath();
    my @sBakDir= ();
    my $sSubSet= '';

    my %hBakDirs = $oTargetPath->getDirRecursive('', 1); # get recurisive file listing for 2 levels
    for my $sMonthDir (keys %hBakDirs) {
        next unless ref $hBakDirs{$sMonthDir}; # dirs point to hashes

        next unless $sMonthDir =~ /\/(\d\d\d\d\-\d\d)\.($sBakSet)$/;

        for my $sDayDir (keys %{$hBakDirs{$sMonthDir}}) {
            next unless ref $hBakDirs{$sMonthDir}->{$sDayDir}; # dirs point to hashes
            # print "$sDayDir??\n";
            next unless $sDayDir =~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?\.(($sBakSource)|($sBakSet))$/; # [a-z] for backward compatibility
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
    return 1 if $self->{_objTarget}->mkdir($sDir);

    $self->log($self->warnMsg("Mkdir '$sDir' failed: $!"));
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
            $self->log($self->errorMsg("Source Object '$sSource' could not be loaded. Skipped."))
        }
        
    } 
    return @oSources;
}

sub backup {
    my $self= shift;

    my $iResult= 0;
    
    my @oSources= $self->get_sourcePaths();

    # mount all target mount objects
    my @sMountMessage= ();
    my $oTargetPath= $self->get_targetPath();
    my $iMountResult= $oTargetPath->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        $self->logError("There was at least one fatal mount error. Backup set skipped.");
        $self->logError(@sMountMessage);
        return 3;
    }
    if (scalar @sMountMessage) {
        $self->log("All mounts completed. More information after log file initialization...");
    }
    $self->log(@sMountMessage);

    # start logging
    my ($sBakMonth, $sBakDay)= $self->_build_bakMonthDay;
    my $sBakSet= $self->get_value("name");
    my $sLogFile= "$sBakMonth-log/$sBakDay.$sBakSet.log";

    if (!$self->get_global_value('switch.pretend') && $self->get_global_value('switch.logging')) {
        $self->_mkdir("$sBakMonth-log");

        my $sLogLink= "$sBakMonth.$sBakSet/$sBakDay.$sBakSet.log";

        my $sLogFileName= $oTargetPath->get_value("PATH") . "/$sLogFile";

        my $sError= $self->get_log->open($sLogFileName, $oTargetPath);
        if ($sError) {
            $self->log($self->warnMsg("Can't open log file \"$sLogFileName\" ($sError). Going on without..."));
        }
        else {
            if (!$self->get_log->is_new()) {

                # TODO: only to file
                $self->log("", "===========================================================================", "");
            }
            $oTargetPath->symlink("../$sLogFile", "$sLogLink");
            $oTargetPath->unlink("current-log.$sBakSet");
            $oTargetPath->symlink($sLogFile, "current-log.$sBakSet");
        }
    }
    $self->log("Logging to: ".$oTargetPath->getFullPath."/$sLogFile") if $self->get_global_value('switch.logging');
    $self->log($self->infoMsg("Rabak Version " . $self->get_global_value("version")));
    $self->logPretending();

    # now try backing up every source 
    my %sNames= ();
    for my $oSource (@oSources) {
        my $sName= $oSource->get_value("name") || '';
        if ($sNames{$sName}) {
            $self->log($self->errorMsg("Name '$sName' of Source Object has already been used. Skipping backup of source."));
            next;
        }
        $self->log($self->infoMsg("Backing up source '$sName'"));
        $sNames{$sName}= 1;
        eval {
            if ($self->backup_setup($oSource) == 0) {
                $iResult++ if $self->backup_run($oSource);
            }
            $self->backup_cleanup($oSource);
        };
        $self->log($self->errorMsg("An error occured during backup: '$@'")) if $@;
    }

    # stop logging
    $self->get_log->close();

    # unmount all target mounts
    $oTargetPath->unmountAll;

    my $sSubject= "successfully finshed";
    $sSubject= "$iResult of " . scalar(@oSources) . " backups failed" if $iResult;
    $sSubject= "*PRETENDED* $sSubject" if $self->get_global_value("switch.pretend");

    # send admin mail
    $self->_mail_log($sSubject);
    
    # return number of failed backups
    return $iResult;
}

sub backup_setup {
    my $self= shift;
    my $oSource= shift;

    my $sSubSet= "";
    my @sBakDir= ();
    my $oTargetPath= $self->get_targetPath();

    my @sMountMessage;
    my $iMountResult= $oSource->mountAll(\@sMountMessage);

    # my @sMountMessage= @{ $self->{_MOUNT_MESSAGE_LIST} };

    unless ($iMountResult) { # fatal mount error
        $self->logError("There was at least one fatal mount error. Backup set skipped.");
        $self->logError(@sMountMessage);
        return 3;
    }

    if (scalar @sMountMessage) {
        $self->log("All mounts completed. More information after log file initialization...");
    }

    unless ($oTargetPath->isDir) {
        $self->logError(@sMountMessage);
        $self->logError("Target \"".$oTargetPath->get_value("PATH")."\" is not a directory. Backup set skipped.");
        return 1;
    }
    unless ($oTargetPath->isWritable) {
        $self->logError(@sMountMessage);
        $self->logError("Target \"".$oTargetPath->get_value("PATH")."\" is not writable. Backup set skipped.");
        return 2;
    }

    my ($sBakMonth, $sBakDay)= $self->_build_bakMonthDay;
    my $sBakSet= $self->get_value("name");
    my $sBakSource= $oSource->get_value("name");

    my $sTarget= "$sBakMonth.$sBakSet";
    $self->_mkdir($sTarget);

    ($sSubSet, @sBakDir)= $self->collect_bakdirs($sBakSet, $sBakSource, $sBakDay);

    $self->set_value("unique_target", "$sBakDay$sSubSet.$sBakSource");
    $sTarget.= "/" . $self->get_value("unique_target");
    $self->set_value("full_target", $oTargetPath->getPath . "/$sTarget");
    # $self->{VALUES}{bak_dirs}= \@sBakDir;

    $self->_mkdir($sTarget);

    $self->log($self->infoMsg("Backup $sBakDay exists, using subset.")) if $sSubSet;
    $self->log($self->infoMsg("Backup start at " . strftime("%F %X", localtime) . ": $sBakSource, $sBakDay$sSubSet, " . $self->get_value("title")));
    $self->log("Source: " . $oSource->get_value("type") . ":" . $oSource->getFullPath);

    $self->log(@sMountMessage);

    $self->{_BAK_DIR_LIST}= \@sBakDir;
    $self->{_BAK_DAY}= $sBakDay;
    $self->{_SUB_SET}= $sSubSet;
    $self->{_TARGET}= $sTarget;

    return 0;
}

sub backup_run {
    my $self= shift;
    my $oSource= shift;

    my $sBakType= $self->get_value("type");

    my @sBakDir= @{ $self->{_BAK_DIR_LIST} };
    my $oTargetPath= $self->get_targetPath;
    my $sBakSetSource= $self->get_value("name") . "-" . $oSource->get_value("name");
    my $sTarget= $self->{_TARGET};

    my $iErrorCode= 0;
    $self->get_log->set_prefix($sBakType);
    $iErrorCode= $oSource->run(@sBakDir);
    $self->get_log->set_prefix();

    if (!$iErrorCode) {
        $self->log("Done!");
    }
    else {
        $self->log($self->errorMsg("Backup failed: " . $oSource->get_last_error));
        $iErrorCode= 9;
    }

    # for backward compatiblity use only dir with source name (not set name like for file linking) 
    my @sKeepDirs= ();
    my $sqBakSource= quotemeta $oSource->get_value("name");
    for my $sBakDir (@sBakDir) {
        push @sKeepDirs, $sBakDir if $sBakDir=~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?\.$sqBakSource$/;
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
                    "The free space on your target \"".$oTargetPath->getFullPath."\" has dropped",
                    "below $iStValue$sStUnit to $iDfAvail$sStUnit."
                )
            );
        }
    }

    return $iErrorCode;
}

sub backup_cleanup {
    my $self= shift;
    my $oSource= shift;

    $oSource->unmountAll;

    # $self->logError(@sMountMessage);

    my $oTargetPath= $self->get_targetPath;
    my $sBakSource= $oSource->get_value("name");
    my $sBakDay= $self->{_BAK_DAY};
    my $sSubSet= $self->{_SUB_SET};

    $self->log($self->infoMsg("Backup done at " . strftime("%F %X", localtime) . ": $sBakSource, $sBakDay$sSubSet")) if $sBakSource && $sBakDay && $sSubSet;
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

    map { $self->logExitError(2, "Every filemask MUST start with \"/\"!") unless /^\//; } @sFileMask;

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
    $self->logExitError(3, "Can't remove! \"$sBakSet.target\" is empty or points to file system root.") if $oTargetPath->getPath eq '' || $oTargetPath->getPath eq '/';

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
        $self->log("Removing " . scalar @{ $aDirs{$_} } . " directories: $_");
        !$self->get_global_value('switch.pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        $self->log("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->get_global_value('switch.pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { $self->log("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
