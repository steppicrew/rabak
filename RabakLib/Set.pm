#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;

use RabakLib::Log;
use RabakLib::Peer::Mountable;
use RabakLib::Peer::Source;
use RabakLib::Peer::Target;

use Data::Dumper;
use File::Spec ();
use Mail::Send;
use POSIX qw(strftime);

# use URI;

use vars qw(@ISA);

@ISA = qw(RabakLib::Conf);

sub new {
    my $class= shift;
    my $sName= shift;
    my $oParentConf= shift;

    my $self= $class->SUPER::new($sName, $oParentConf);

    $self->{ERRORCODE}= 0;
    $self->{DEBUG}= 0;

    $self->{_TARGET_OBJECT}= undef;

    $self->set_value("name", $sName);
    bless $self, $class;
}

sub newFromConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::newFromConf($oOrigConf);

    # FIXME: Where is ERROR used? Use get_validation_message on returned instance!

    $new->{ERROR}= $new->get_validation_message();
    return $new;
}

sub get_validation_message {
    my $self= shift;
    return $self->get_value_required_message("title")
        || $self->get_value_required_message("source")
        || $self->get_value_required_message("target");
}

# sub _need_value {
#     my $self= shift;
#     my $sField= shift;
#
#     return "Required value \"" . $self->get_value("name") . ".$sField\" missing." unless defined $self->{VALUES}{$sField};
#     return undef;
# }

# sub _validate {
#     my $self= shift;
#
#     return $self->_need_value('title') || $self->_need_value('source') || $self->_need_value('target');
# }

sub sort_show_key_order {
    my $self= shift;
    ("title", "source", "target", $self->SUPER::sort_show_key_order());
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    logger->set_stdout_prefix("# ");
    
    my $aResult= [];
    
    push @$aResult, "",
        "#" x 80,
        "# Configuration for \"$self->{NAME}\"",
        "#" x 80;

    my @oSources= $self->get_sourcePeers();
    my $oTarget= $self->get_targetPeer();

    push @$aResult, @{$self->SUPER::show($hConfShowCache)};

    for my $oSource (@oSources) {
        push @$aResult, @{$oSource->show($hConfShowCache, $oTarget)};
    }
    
    push @$aResult, @{$oTarget->show($hConfShowCache)};
    
    my $oRootConf= $self->find_scope("/switch");
    my $oSwitches= $oRootConf->get_property("switch");
    if (defined $oSwitches && ref $oSwitches) {
        push @$aResult, "", "# Switches:", @{$oSwitches->show()};
    }
    
    # print all not already shown references
    my @sSubResult= $self->showUncachedReferences($hConfShowCache);
    push @$aResult, "", "# Misc references:", @sSubResult if scalar @sSubResult > 1;
    push @$aResult, "";
    
    return $self->simplifyShow($aResult);
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub _timestr {
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

sub logPretending {
    my $self= shift;
    return unless $self->get_switch('pretend');

    logger->info("", "**** Only pretending, no changes are made! ****", "");
}

sub _mail {
    my $self= shift;
    my ($sSubject, $fBody) = @_;
    
    my $sMailAddress= $self->get_value('email'); 

    return 0 if $self->get_switch('pretend'); 
    return 0 unless $sMailAddress;

    my $oMail = new Mail::Send Subject => $sSubject, To => $sMailAddress;
    # $msg->cc('user@host');
    my $fh = $oMail->open;
    my $sLine;
    my $fChompNL= sub {
        my $sLine= $fBody->();
        return undef unless defined $sLine;
        chomp $sLine;
        return "$sLine\n";
    };
    print $fh $sLine while defined ($sLine = $fChompNL->());
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

    my $sFileName= logger->get_messages_file();
    my $fh;
    open $fh, "<$sFileName" or $fh= undef;
    my $fBody = sub {<$fh>};
    unless (defined $fh) {
        my @sBody= ("Error openening file '$sFileName'");
        $fBody = sub {shift @sBody};
    }

    my $result = $self->_mail($sSubject, $fBody);
    close $fh if defined $fh;
    return $result;
}

sub _mail_warning {
    my $self= shift;
    my ($sSubject, @sBody) = @_;

    return $self->_mail("RABAK WARNING: $sSubject", sub {shift @sBody});
}

# -----------------------------------------------------------------------------
#  ...
# -----------------------------------------------------------------------------

sub get_targetPeer {
    my $self= shift;

    unless ($self->{_TARGET_OBJECT}) {
        my @oConfs= $self->resolveObjects("target");
        my $oConf= shift @oConfs;
        logger->error("Specifying more than one target is not allowed") if scalar @oConfs;
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' targets: should this set parent for inheriting values?
            $oConf= RabakLib::Conf->new(undef, $self);
            $oConf->set_value("path", $sPath);
        }
        $self->{_TARGET_OBJECT}= RabakLib::Peer::Target->newFromConf($oConf);
        ## $self->{_TARGET_OBJECT}->set_value("switch.warn_on_remote_access", );
    }
    return $self->{_TARGET_OBJECT};
}

# collect all backup dirs
sub collect_bakdirs {
    my $self= shift;
    my @sqBakSet= map {$_ eq '' ? '.{0}' : quotemeta $_} @{shift @_};
    my @sqBakSource= map {$_ eq '' ? '.{0}' : quotemeta $_} @{shift @_};
    my $sSubSetBakDay= shift || 0;

    my $sqBakSet= "(" . join(")|(", @sqBakSet) . ")";
    my $sqBakSource= "(" . join(")|(", @sqBakSource) . ")";

    my $oTargetPeer= $self->get_targetPeer();
    my %sBakDirs= ();
    my $sSubSet= '';

    my %hBakDirs = $oTargetPeer->getDirRecursive('', 1); # get recursive file listing for 2 levels

    print Dumper(\%hBakDirs);

    for my $sMonthDir (keys %hBakDirs) {
        # skip all non-dirs
        next unless ref $hBakDirs{$sMonthDir};
        # skip all dirs not containing any bak set extension
        next unless $sMonthDir =~ /\/\d\d\d\d\-\d\d($sqBakSet)$/;

        for my $sDayDir (keys %{$hBakDirs{$sMonthDir}}) {
            # skip all non-dirs
            next unless ref $hBakDirs{$sMonthDir}->{$sDayDir};
            # [a-z] for backward compatibility
            next unless $sDayDir =~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?($sqBakSource)$/;
            my $sCurSubSetBakDay= $1;
            my $sCurSubSet= $2 || '';
            if ($sSubSetBakDay eq $sCurSubSetBakDay) {
                die "Maximum of 1000 backups reached!" if $sCurSubSet eq '_999';
                if (!$sCurSubSet) {
                    $sSubSet= '_001' if $sSubSet eq '';
                }
                elsif ($sSubSet le $sCurSubSet) {
                    $sCurSubSet=~ s/^[\-_]0*//;
                    $sSubSet= sprintf("_%03d", $sCurSubSet + 1);
                }
            }
            $sBakDirs{$sCurSubSetBakDay}= [] unless $sBakDirs{$sCurSubSetBakDay};
            push @{$sBakDirs{$sCurSubSetBakDay}}, $sDayDir;
            # print "$sDayDir\n";
        }
    }

    my @sResult = ();
    for my $sBakDay (sort {$b cmp $a} keys %sBakDirs) {
        my @sBakDirs= @{$sBakDirs{$sBakDay}};
        for $sqBakSet (@sqBakSet) {
            for $sqBakSource (@sqBakSource) {
                my $regExp= qr/\/\d\d\d\d\-\d\d$sqBakSet\/\d\d\d\d\-\d\d\-\d\d[a-z]?([\-_]\d{3})?$sqBakSource$/;
                push @sResult, sort {$b cmp $a} grep {/$regExp/} @sBakDirs;
                # remove found dirs to prevent duplicate result strings
                @sBakDirs = grep {!/$regExp/} @sBakDirs;
            }
        }
    }

    unshift @sResult, $sSubSet if $sSubSetBakDay;

    return @sResult;
}

# -----------------------------------------------------------------------------
#  Little Helpers
# -----------------------------------------------------------------------------

sub _mkdir {
    my $self= shift;
    my $sDir= shift;

    return 1 if $self->get_switch('pretend');

    # TODO: set MASK ?
    # return 1 if $self->{_TARGET_OBJECT}->mkdir($sDir);

    return 1 if $self->get_targetPeer()->mkdir($sDir);

    logger->warn("Mkdir '$sDir' failed: $!");
    return 0;
}

# -----------------------------------------------------------------------------
#  Backup
# -----------------------------------------------------------------------------

sub get_sourcePeers {
    my $self= shift;
    
    my @oConfs= $self->resolveObjects("source");
    my @oSources= ();
    for my $oConf (@oConfs) {
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' sources: should this set parent for inheriting values?
            $oConf= RabakLib::Conf->new(undef, $self);
            $oConf->set_value("path", $sPath);
        }
        push @oSources, RabakLib::Peer::Source->Factory($oConf);
    } 
    return @oSources;
}

sub getPathExtension {
    my $self= shift;
    my $sExt = $self->get_value("path_extension", $self->get_value("name", ""));
    return "" if $sExt eq "";
    return ".$sExt";
}

sub getAllPathExtensions {
    my $self= shift;
    my $obj= shift || $self;
    
    return [
        $obj->getPathExtension(),
        map {$_ eq "" ? "" : ".$_"}
            grep {! ref} $obj->resolveObjects("previous_path_extensions"),
    ];
}

sub backup {
    my $self= shift;

    my $iSuccessCount= 0;
    my $iResult= 0; 
    
    logger->init($self);
    logger->set_category($self->get_value("name"));
    
    logger->info("Rabak Version " . $self->get_switch("version"). " on \"" . $self->get_switch("hostname") . "\" as user \"" . getpwuid($>) . "\"");
    logger->info("Command line: " . $self->get_switch("commandline"));
    logger->info("Configuration read from: '" . $self->get_switch("configfile") . "'");

    my @oSources= $self->get_sourcePeers();

    # mount all target mount objects
    my @sMountMessage= ();
    my $oTargetPeer= $self->get_targetPeer();
    my $iMountResult= $oTargetPeer->mountAll(\@sMountMessage);

    unless ($iMountResult) { # fatal mount error
        logger->error("There was at least one fatal mount error on target. Backup set skipped.");
        logger->error(@sMountMessage);
        $iResult= -3;
        goto cleanup;
    }
    logger->log(@sMountMessage);

    # check target dir
    unless ($oTargetPeer->isDir) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$oTargetPeer->get_value("path")."\" is not a directory. Backup set skipped.");
        $iResult= -1;
        goto cleanup;
    }
    unless ($oTargetPeer->isWritable) {
        logger->error(@sMountMessage);
        logger->error("Target \"".$oTargetPeer->get_value("path")."\" is not writable. Backup set skipped.");
        $iResult= -2;
        goto cleanup;
    }

    my $sBakMonth= strftime("%Y-%m", localtime);
    my $sBakDay= strftime("%Y-%m-%d", localtime);

    my $sBakSetExt= $self->getPathExtension();

    # create target month dir
    my $sTarget= "$sBakMonth$sBakSetExt";
    $self->_mkdir($sTarget);

    # start logging
    my $sLogDir= "$sBakMonth-log";
    my $sLogFile= "$sLogDir/$sBakDay$sBakSetExt.log";
    my $sLogFileName= $oTargetPeer->getPath() . "/$sLogFile";

    if (!$self->get_switch('pretend') && $self->get_switch('logging')) {
        $self->_mkdir($sLogDir);
        my $sLogLink= "$sTarget/$sBakDay$sBakSetExt.log";


        my $sError= logger->open($sLogFileName, $oTargetPeer);
        if ($sError) {
            logger->warn("Can't open log file \"$sLogFileName\" ($sError). Going on without...");
        }
        else {
            $oTargetPeer->symlink("../$sLogFile", "$sLogLink");
            my $sCurrentLogFileName= "current-log$sBakSetExt";
            $oTargetPeer->unlink($sCurrentLogFileName);
            $oTargetPeer->symlink($sLogFile, $sCurrentLogFileName);
        }
    }
    logger->info("Logging to: $sLogFileName") if $self->get_switch('logging');
    $self->logPretending();

    # now try backing up every source 
    my %sNames= ();
    for my $oSource (@oSources) {
        my $sName= $oSource->get_value("name", "");
        $oSource->set_value("name", "") if $sName=~ s/^\*//;
        if ($sNames{$sName}) {
            logger->error("Name '$sName' of Source Object has already been used. Skipping backup of source.");
            next;
        }
        $sNames{$sName}= 1;
        eval {
            my $hBackupData= {
                source => $oSource,
                target => $oTargetPeer,
                target_dir => $sTarget,
                bak_day => $sBakDay,
            };
            if ($self->_backup_setup($hBackupData) == 0) {
                $iSuccessCount++ unless $self->_backup_run($hBackupData);
            }
            $self->_backup_cleanup($hBackupData);
        };
        logger->error("An error occured during backup: '$@'") if $@;
        $oSource->cleanupTempfiles();
    }

    $iResult= scalar(@oSources) - $iSuccessCount;

cleanup:
    $oTargetPeer->cleanupTempfiles();
    my $aDf = $oTargetPeer->checkDf();
    if (defined $aDf) {
        logger->warn(join " ", @$aDf);
        $self->_mail_warning("disc space too low", @$aDf);
    }

    # stop logging
    logger->close();
    
    # unmount all target mounts
    $oTargetPeer->unmountAll;

    my $sSubject= "successfully finished";
    $sSubject= "$iSuccessCount of " . scalar(@oSources) . " backups $sSubject" if $iResult;
    $sSubject= "ERROR: all backups failed" unless $iSuccessCount;
    $sSubject= "*PRETENDED* $sSubject" if $self->get_switch("pretend");

    # send admin mail
    $self->_mail_log($sSubject);
    
    # return number of failed backups or error code (negative)
    return $iResult;
}

sub _backup_setup {
    my $self= shift;
    my $hBackupData= shift;
    
    my $oSource= $hBackupData->{source};

    my $sSubSet= "";
    my @sBakDir= ();
    my $oTarget= $hBackupData->{target};

    return 1 unless $oSource->prepareBackup();

    my $sBakSetExt= $self->getPathExtension();
    my $sBakSourceExt= $oSource->getPathExtension();
    my $sBakSourceName= $oSource->get_value("name");
    
    my $sBakDay= $hBackupData->{bak_day};
    ($sSubSet, @sBakDir)= $self->collect_bakdirs(
        $self->getAllPathExtensions(),
        $self->getAllPathExtensions($oSource),
        $sBakDay,
    );

    my $sUniqueTarget= "$sBakDay$sSubSet$sBakSourceExt";
    $hBackupData->{unique_name}= $sUniqueTarget;
    my $sTarget= "$hBackupData->{target_dir}/$sUniqueTarget";
    $hBackupData->{full_target}= $oTarget->getPath($sTarget);

    $self->_mkdir($sTarget);

    logger->info("Backup $sBakDay exists, using subset.") if $sSubSet;
    logger->info("Backup start at " . strftime("%F %X", localtime) . ": $sBakSourceName, $sBakDay$sSubSet, " . $self->get_value("title"));
    logger->info("Source: " . $oSource->getFullPath());

    $hBackupData->{bak_dir_list}= \@sBakDir;
    $hBackupData->{sub_set}= $sSubSet;
    $hBackupData->{rel_target}= $sTarget;

    return 0;
}

sub _backup_run {
    my $self= shift;
    my $hBackupData= shift;
    
    my $oSource= $hBackupData->{source};
    my $oTarget= $hBackupData->{target};
    my @sBakDir= @{ $hBackupData->{bak_dir_list} };
    my $sBakSetSourceExt= $self->getPathExtension();

    my $sSourceName= $oSource->get_value("name");
    $sBakSetSourceExt .= "-$sSourceName" if $sSourceName;

    my $sTarget= $hBackupData->{rel_target};

    my $iErrorCode= 0;
    logger->set_prefix($oSource->get_value("type"));
    $iErrorCode= $oSource->run(
        $oTarget,
        $hBackupData->{full_target},
        $hBackupData->{unique_name},
        $self->get_switch('pretend'),
        @sBakDir
    );
    logger->set_prefix();

    if (!$iErrorCode) {
        logger->info("Done!");
    }
    else {
        logger->error("Backup failed: " . $oSource->get_last_error);
        $iErrorCode= 9;
    }

    unless ($self->get_switch('pretend')) {
        $oTarget->remove_old($oSource->get_value("keep"), @sBakDir) unless $iErrorCode;    # only remove old if backup was done
        $oTarget->unlink("current$sBakSetSourceExt");
        $oTarget->symlink("$sTarget", "current$sBakSetSourceExt");
    }

    return $iErrorCode;
}

sub _backup_cleanup {
    my $self= shift;
    my $hBackupData= shift;
    
    my $oSource= $hBackupData->{source};
    $oSource->finishBackup();

    my $sBakSource= $oSource->get_value("name");
    my $sBakDay= $hBackupData->{bak_day};
    my $sSubSet= $hBackupData->{sub_set};

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

    map { logger->exitError(2, "Every filemask MUST start with \"/\"!") unless /^\//; } @sFileMask;

    return 2 unless scalar @sFileMask && defined $sFileMask[0];

    $self->logPretending();

    my %aDirs= ();
    my %aFiles= ();
    my %iFoundMask= ();

    my $sBakSet= $self->get_value("name");
    my $sBakSetDay= $sBakSet;
    $sBakSetDay.= "-" . $oSource->get_value("name") if $oSource->get_value("name");
    my $oTargetPeer= $self->get_targetPeer();

    # TODO: Make a better check!
    logger->exitError(3, "Can't remove! \"$sBakSet.target\" is empty or points to file system root.") if $oTargetPeer->getPath eq '' || $oTargetPeer->getPath eq '/';

    die "wrong parameters for collect_bakdirs()";
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
        !$self->get_switch('pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        logger->log("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->get_switch('pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { logger->log("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
