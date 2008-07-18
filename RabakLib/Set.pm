#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;
no warnings 'redefine';

use RabakLib::Log;
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

sub GetAllPathExtensions {
    my $class= shift;
    my $obj= shift;
    
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

    my $oTargetPeer= $self->get_targetPeer();
    my @oSourcePeers= $self->get_sourcePeers();

    $iResult= $oTargetPeer->prepareBackup(
        $self->GetAllPathExtensions($self),
        $self->get_switch('pretend'),
    );
    goto cleanup if $iResult;

    $oTargetPeer->prepareLogging($self->get_switch('pretend')) if $self->get_switch('logging');

    # now try backing up every source 
    my %sNames= ();
    for my $oSourcePeer (@oSourcePeers) {
        my $sName= $oSourcePeer->get_value("name", "");
        $oSourcePeer->set_value("name", "") if $sName=~ s/^\*//;
        if ($sNames{$sName}) {
            logger->error("Name '$sName' of Source Object has already been used. Skipping backup of source.");
            next;
        }
        $sNames{$sName}= 1;
        eval {
            my $iBackupResult= $self->_backup_setup($oSourcePeer, $oTargetPeer);
            unless ($iBackupResult) {
                $iBackupResult= $self->_backup_run($oSourcePeer, $oTargetPeer);
                $iSuccessCount++ unless $iBackupResult;
            }
            $self->_backup_cleanup($oSourcePeer, $oTargetPeer, $iBackupResult);
        };
        logger->error("An error occured during backup: '$@'") if $@;
    }

    $iResult= scalar(@oSourcePeers) - $iSuccessCount;

cleanup:
    # TODO: move _mail* to logger and do df-check in Traget.pm
    my $aDf = $oTargetPeer->checkDf();
    if (defined $aDf) {
        logger->warn(join " ", @$aDf);
        $self->_mail_warning("disc space too low", @$aDf);
    }

    $oTargetPeer->finishLogging();
    $oTargetPeer->finishBackup();

    my $sSubject= "successfully finished";
    $sSubject= "$iSuccessCount of " . scalar(@oSourcePeers) . " backups $sSubject" if $iResult;
    $sSubject= "ERROR: all backups failed" unless $iSuccessCount;
    $sSubject= "*PRETENDED* $sSubject" if $self->get_switch("pretend");

    # send admin mail
    $self->_mail_log($sSubject);
    
    # return number of failed backups or error code (negative)
    return $iResult;
}

sub _backup_setup {
    my $self= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;
    
    logger->info("Backup start at " . strftime("%F %X", localtime) . ": "
        . ($oSourcePeer->getName() || $oSourcePeer->getFullPath()) . ", "
        . $self->get_value("title")
    );
    logger->incIndent();

    $oTargetPeer->prepareSourceBackup(
        $oSourcePeer,
        $self->get_switch('pretend'),
    );

    return $oSourcePeer->prepareBackup($self->get_switch('pretend'));
}

sub _backup_run {
    my $self= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;
    
    return $oSourcePeer->run(
        $oTargetPeer,
        $self->get_switch('pretend'),
    );
}

sub _backup_cleanup {
    my $self= shift;
    my $oSourcePeer= shift;
    my $oTargetPeer= shift;
    my $iBackupResult= shift;
    
    my $sSourceSet= $oTargetPeer->getSourceSubdir();

    $oSourcePeer->finishBackup($iBackupResult, $self->get_switch('pretend'));

    if ($iBackupResult) {
        logger->error("Backup failed: " . $oSourcePeer->get_last_error);
        $iBackupResult= 9;
    }
    else {
        logger->info("Done!");
    }

    $oTargetPeer->finishSourceBackup($iBackupResult, $self->get_switch('pretend'));

    logger->decIndent();
    logger->info("Backup done at "
        . strftime("%F %X", localtime) . ": "
        . ($oSourcePeer->getName() || $oSourcePeer->getFullPath()) . ", "
        . $sSourceSet
    );
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
