#!/usr/bin/perl

package Rabak::Job;

use warnings;
use strict;
no warnings 'redefine';

use Rabak::Log;
use Rabak::Peer::Source;
use Rabak::Peer::Target;
use Rabak::Backup;
use Rabak::Version;
use Rabak::Util;

use Data::Dumper;
use File::Spec ();
use POSIX qw(strftime);

# use URI;

use vars qw(@ISA);

@ISA = qw(Rabak::Conf);

sub new {
    my $class= shift;
    my $sName= shift;
    my $oParentConf= shift;

    my $self= $class->SUPER::new($sName, $oParentConf);

    $self->{ERRORCODE}= 0;
    $self->{DEBUG}= 0;

    $self->{_TARGET_OBJECT}= undef;

    $self->setValue("name", $sName);
    bless $self, $class;
}

sub newFromConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::newFromConf($oOrigConf);

    # FIXME: Where is ERROR used? Use getValidationMessage on returned instance!

    $new->{ERROR}= $new->getValidationMessage();
    return $new;
}

# IMPORTANT: define all used properties here, order will be used for show
sub propertyNames {
    my $self= shift;

    return ('title', 'source', 'target', 'email', $self->SUPER::propertyNames(), 'path_extension', 'previous_path_extensions', 'command_after');
}

sub GetJobs {
    my $class= shift;
    my $oConf= shift;
    my $sJob= shift || '*';

    my @aJobs= map { $class->newFromConf($_) } grep {
        ref $_
        && $_->getRawValue("title")
        && $_->getRawValue("source")
        && $_->getRawValue("target");
    } map {
        ($oConf->resolveObjects($_))[0]
    } sort keys %{ $oConf->{VALUES} };

    return @aJobs if $sJob eq '*';

    for my $oJob (@aJobs) {
        return ($oJob) if $oJob->getFullName() eq $sJob;
    }
    return ();
}

sub getValidationMessage {
    my $self= shift;

    return $self->getValueRequiredMessage("title")
        || $self->getValueRequiredMessage("source")
        || $self->getValueRequiredMessage("target");
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    logger->setStdoutPrefix("#");
    
    my $aResult= [];
    
    push @$aResult, "",
        "#" x 80,
        "# Configuration for \"$self->{NAME}\"",
        "#" x 80;

    my @oSources= $self->getSourcePeers();
    my $oTarget= $self->getTargetPeer();

    push @$aResult, @{$self->SUPER::show($hConfShowCache)};

    push @$aResult, map { @{$_->show($hConfShowCache, $oTarget)} } @oSources;
    
    push @$aResult, @{$oTarget->show($hConfShowCache)};
    
    my $oRootConf= $self->findScope("/switch");
    my $oSwitches= $oRootConf->getProperty("switch");
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

sub getTargetPeer {
    my $self= shift;

    unless ($self->{_TARGET_OBJECT}) {
        my @oConfs= $self->resolveObjects("target");
        my $oConf= shift @oConfs;
        logger->error("Specifying more than one target is not allowed") if scalar @oConfs;
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' targets: should this set parent for inheriting values?
            $oConf= Rabak::Conf->new(undef, $self);
            $oConf->setValue("path", $sPath);
        }
        $self->{_TARGET_OBJECT}= Rabak::Peer::Target->newFromConf($oConf);
        ## $self->{_TARGET_OBJECT}->setValue("switch.warn_on_remote_access", );
    }
    return $self->{_TARGET_OBJECT};
}

# -----------------------------------------------------------------------------
#  Backup
# -----------------------------------------------------------------------------

sub getSourcePeers {
    my $self= shift;
    
    my @oConfs= $self->resolveObjects("source");
    my @oSources= ();
    for my $oConf (@oConfs) {
        unless (ref $oConf) {
            my $sPath= $oConf;
            # TODO: for 'anonymous' sources: should this set parent for inheriting values?
            $oConf= Rabak::Conf->new(undef, $self);
            $oConf->setValue("path", $sPath);
        }
        push @oSources, Rabak::Peer::Source->newFromConf($oConf);
    } 
    return @oSources;
}

sub getPathExtension {
    my $self= shift;
    my $sExt = $self->getValue("path_extension", $self->getName());
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

sub getMetaDir {
    my $self= shift;
    my $sSubDir= shift || '';
    
    my $sDir= Rabak::Util->GetVlrDir() . '/' . $self->getTargetPeer()->getUuid() . '/' . $sSubDir;
    Rabak::Peer->new()->mkdir($sDir);
    return $sDir;
}

sub backup {
    my $self= shift;

    my $iSuccessCount= 0;
    my $iResult= 0; 
    
    my %LogOpts= ();
    for my $sLogOpt ('pretend', 'logging', 'verbose', 'quiet') {
        $LogOpts{ucfirst $sLogOpt} = $self->getSwitch($sLogOpt);
    }
    $LogOpts{"Email"} = $self->getValue("email");
    $LogOpts{"Name"} = $self->getName();
    $LogOpts{"Run_command"}= $self->getValue("command_after");
    logger->setOpts(\%LogOpts);

    logger->setCategory($self->getName());
    
    logger->info("Rabak Version " . VERSION() . " on \"" . $self->cmdData("hostname") . "\" as user \"" . $self->cmdData("user") . "\"");
    logger->info("Command line: " . $self->cmdData("command_line"));
    logger->info("Configuration read from: '" . $self->cmdData("config_file") . "'");

    my $oTargetPeer= $self->getTargetPeer();
    my @oSourcePeers= $self->getSourcePeers();

    if ($self->getSwitch('pretend')) {
        $oTargetPeer->setPretend(1);
        $_->setPretend(1) for @oSourcePeers;
    }

    my $oSessionDataConf= Rabak::Conf->new('*');
    $oSessionDataConf->setQuotedValue('cmdline', $self->cmdData("command_line"));
    $oSessionDataConf->setQuotedValue('time.start', Rabak::Util->GetTimeString());

    my $hJobData= $oTargetPeer->prepareForBackup($self->GetAllPathExtensions($self));
    $oSessionDataConf->setQuotedValue('target.uuid', $oTargetPeer->getUuid());

    $self->_syncMetaDataFromTarget();

    $iResult= $hJobData->{ERROR};

    unless ($iResult) {

        $oTargetPeer->initLogging($hJobData) if $self->getSwitch('logging');

        my $hDoneSources= {};
        # now try backing up every source 
        for my $oSourcePeer (@oSourcePeers) {
            my $sSourceName= $oSourcePeer->getFullName();
            $oSourcePeer->setValue('name', '') if $sSourceName=~ s/^\*//;
            if ($hDoneSources->{$sSourceName}) {
                logger->error("Source object named \"$sSourceName\" was already backed up. Skipping.");
                next;
            }
            my $oSourceDataConf= Rabak::Conf->new('source_' . scalar(keys %$hDoneSources), $oSessionDataConf);
            $hDoneSources->{$sSourceName}= $oSourceDataConf;
            $oSourceDataConf->setQuotedValue('fullname', $sSourceName);
            $oSessionDataConf->setQuotedValue($oSourceDataConf->getName(), $oSourceDataConf);
            my $oBackup= Rabak::Backup->Factory($oSourcePeer, $oTargetPeer);
            eval {
                unless ($oBackup->run($hJobData, $oSourceDataConf)) {
                    $iSuccessCount++;
                }
                1;
            };
            if ($@) {
                logger->error("An error occured during backup: '$@'");
                $oSourceDataConf->setQuotedValue('error', $@);
            }
        }

        $oSessionDataConf->setValue('sources', join ", ", map { '&' . $_->getName() } values %$hDoneSources);

        $iResult= scalar(@oSourcePeers) - $iSuccessCount;
    }

    my $fWriteSessionData= sub {
        return if $self->getSwitch('pretend');

        $oSessionDataConf->setQuotedValue('time.end', Rabak::Util->GetTimeString());
        my $sSessionName= 'session.'
            . $oSessionDataConf->getValue('time.start') . '.'
            . $oSessionDataConf->getValue('time.end');
        my $sMetaSubDir= $self->getFullName();
        my $sMetaDir= $self->getMetaDir($sMetaSubDir);
        return unless $sMetaDir;

        my $sMetaFile= $sMetaDir . '/' . $sSessionName;
        $oSessionDataConf->writeToFile($sMetaFile);

        $self->_syncMetaDataToTarget();
    };
    
    $oTargetPeer->finishBackup($hJobData, $fWriteSessionData);
    
    my $sSubject= "successfully finished";
    $sSubject= "$iSuccessCount of " . scalar(@oSourcePeers) . " backups $sSubject" if $iResult;
    $sSubject= "ERROR: all backups failed" unless $iSuccessCount;
    $sSubject= "*PRETENDED* $sSubject" if $self->getSwitch("pretend");

    # send admin mail
    logger->mailLog($sSubject);
    
    # return number of failed backups or error code (negative)
    return $iResult;
}

# sync session files and inodes/inode_files.db FROM target
# TODO: do something if sync fails (disk full etc.)
sub _syncMetaDataFromTarget {
    my $self= shift;
    
    my $oTargetPeer= $self->getTargetPeer();
    my $oLocalPeer= Rabak::Peer->new();

    my $sIncludePath= '';
    my @sOpts= (
        #           ignore empty dirs                                  copy dirlinks as dirs
        '--update', '--prune-empty-dirs', '--archive', '--hard-links', '--copy-dirlinks',
        '--include=/', '--include=/meta/', '--include=/meta/*/', '--include=/meta/*/**',
        '--include=/meta/' . Rabak::Util->GetControllerUuid() . '.*',
        '--exclude=/**',
    );
    
    my $sTargetPath= $self->getMetaDir();
    
    logger->verbose("Syncing meta data from target to local meta dir \"$sTargetPath\"...");
    logger->incIndent();
    my $iResult= $oTargetPeer->rsync(
        source_files => 'meta/',
        target_path => $self->getMetaDir(),
        target_peer => $oLocalPeer,
        opts => \@sOpts,
        log_level => logger->LOG_DEBUG_LEVEL,
    );
    logger->error(
        "Error syncing from target: \""
        . $oTargetPeer->getLastError() . "\""
    ) if $oTargetPeer->getLastError();

    logger->decIndent();
    logger->verbose('done');
    return $iResult;
}

# sync session files and inodes/inode_files.db TO target
sub _syncMetaDataToTarget {
    my $self= shift;
    
    my $oTargetPeer= $self->getTargetPeer();
    my $oLocalPeer= Rabak::Peer->new();

    #           only if newer                            only existing  keep dir links on target
    my @sOpts= ('--update', '--archive', '--hard-links', '--existing', '--keep-dirlinks');
    
    my $sSourcePath= $self->getMetaDir();
    
    logger->verbose("Syncing meta data from local meta dir \"$sSourcePath\" to target...");
    logger->incIndent();
    my $iResult= $oLocalPeer->rsync(
        source_files => "$sSourcePath/*",
        target_path => '',
        target_peer => $oTargetPeer,
        opts => \@sOpts,
        log_level => logger->LOG_DEBUG_LEVEL,
    );
    logger->error(
        "Error syncing data to target: \""
        . $oLocalPeer->getLastError() . "\""
    ) if $oLocalPeer->getLastError();

    logger->decIndent();
    logger->verbose('done');
    return $iResult;
}

# -----------------------------------------------------------------------------
#  Remove file
# -----------------------------------------------------------------------------

sub _rmFile {

    die "The current _rmFile is flawed. It will be available again in the next release!";

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

    my $sJob= $self->getName();
    my $sJobDay= $sJob;
    my $sSourceName= $oSource->getName();
    $sJobDay.= "-$sSourceName"  if $sSourceName;
    my $oTargetPeer= $self->getTargetPeer();

    # TODO: Make a better check!
    logger->exitError(3, "Can't remove! \"$sJob.target\" is empty or points to file system root.") if $oTargetPeer->getPath eq '' || $oTargetPeer->getPath eq '/';

    die "wrong parameters for collect_bakdirs()";
    my @sBakDir= $self->collect_bakdirs($sJob, $sJobDay);

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
        !$self->getSwitch('pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        logger->log("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->getSwitch('pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { logger->log("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
