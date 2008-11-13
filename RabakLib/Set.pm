#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;
no warnings 'redefine';

use RabakLib::Log;
use RabakLib::Peer::Source;
use RabakLib::Peer::Target;
use RabakLib::Version;

use Data::Dumper;
use File::Spec ();
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

sub sort_show_key_order {
    my $self= shift;
    (
        "title", "source", "target",
        $self->SUPER::sort_show_key_order(),
        "path_extension", "previous_path_extension",
    );
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    logger->set_stdout_prefix("#");
    
    my $aResult= [];
    
    push @$aResult, "",
        "#" x 80,
        "# Configuration for \"$self->{NAME}\"",
        "#" x 80;

    my @oSources= $self->get_sourcePeers();
    my $oTarget= $self->get_targetPeer();

    push @$aResult, @{$self->SUPER::show($hConfShowCache)};

    push @$aResult, map { @{$_->show($hConfShowCache, $oTarget)} } @oSources;
    
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
    my $sExt = $self->get_value("path_extension", $self->getName());
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
    
    my %LogOpts= ();
    for my $sLogOpt ('pretend', 'logging', 'verbose', 'quiet') {
        $LogOpts{ucfirst $sLogOpt} = $self->get_switch($sLogOpt);
    }
    $LogOpts{"Email"} = $self->get_value("email");
    $LogOpts{"Name"} = $self->getName();
    logger->setOpts(\%LogOpts);

    logger->set_category($self->getName());
    
    logger->info("Rabak Version " . VERSION() . " on \"" . $self->cmdData("hostname") . "\" as user \"" . $self->cmdData("user") . "\"");
    logger->info("Command line: " . $self->cmdData("command_line"));
    logger->info("Configuration read from: '" . $self->cmdData("config_file") . "'");

    my $oTargetPeer= $self->get_targetPeer();
    my @oSourcePeers= $self->get_sourcePeers();

    $iResult= $oTargetPeer->prepareBackup(
        $self->GetAllPathExtensions($self),
        $self->get_switch('pretend'),
    );
    goto cleanup if $iResult;

    $oTargetPeer->initLogging($self->get_switch('pretend')) if $self->get_switch('logging');

    # now try backing up every source 
    my %sNames= ();
    for my $oSourcePeer (@oSourcePeers) {
        my $sName= $oSourcePeer->getName();
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
    $oTargetPeer->finishBackup();

    my $sSubject= "successfully finished";
    $sSubject= "$iSuccessCount of " . scalar(@oSourcePeers) . " backups $sSubject" if $iResult;
    $sSubject= "ERROR: all backups failed" unless $iSuccessCount;
    $sSubject= "*PRETENDED* $sSubject" if $self->get_switch("pretend");

    # send admin mail
   logger->mailLog($sSubject);
    
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

    my $sBakSet= $self->getName();
    my $sBakSetDay= $sBakSet;
    my $sSourceName= $oSource->getName();
    $sBakSetDay.= "-$sSourceName"  if $sSourceName;
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
