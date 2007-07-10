#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;

use RabakLib::Conf;
use RabakLib::Log;
use RabakLib::Path;

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
    my $sName= shift || '';
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

    $self->{LOG_FILE}= RabakLib::Log->new($hConf);
    $self->{LOG_FILE}->set_category($sName);

    # my $xx= "file://C:/etc/passwd";
    # my $uri= URI->new($xx); # self->{VALUES}{source});
    # print Dumper($uri);

    # print "\n" . $uri->scheme;
    # print "\n" . $uri->opaque;
    # print "\n" . $uri->path;
    # print "\n" . $uri->fragment;
    # exit;

    if (defined $self->{VALUES}{source} && !ref $self->{VALUES}{source} && $self->{VALUES}{source} =~ /^([a-z]+):(.*)/) {
        $self->{VALUES}{type}= $1;
        $self->{VALUES}{source}= $2;
    }
    else {
        $self->{VALUES}{type}= 'file' unless defined $self->{VALUES}{type} || ref $self->{VALUES}{type};
    }

    unless ($bSkipValidation) {
        $self->{ERROR}= $self->_validate();

        # TODO: fix
        # if ($self->{VALUES}{type} !~ /^(file|pgsql|mysql)$/) {
        #     return "Backup set type of \"$sName.source\" must be \"file\", \"pgsql\" or \"mysql\". (" . $self->{VALUES}{source} . ")";
        # }
    }
    $self->{VALUES}{name}= $sName;

    bless $self, $class;
}

sub _need_value {
    my $self= shift;
    my $sField= shift;

    return "Required value \"" . $self->{VALUES}{name} . ".$sField\" missing." unless defined $self->{VALUES}{$sField};
    return undef;
}

sub _validate {
    my $self= shift;

    return $self->_need_value('title') || $self->_need_value('source') || $self->_need_value('target');
}

sub _show {}

sub show {
    my $self= shift;
    my $sKey= shift || $self->{NAME};
    $self->SUPER::show($sKey);

    my $sType= $self->{VALUES}{type};
    eval {
        require "RabakLib/Type/" . ucfirst($sType) . ".pm";
        my $sClass= "RabakLib::Type::" . ucfirst($sType);
        my $oSet= $sClass->new($self);
        $oSet->_show;
    } or die $!;

}

sub get_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    $sName=~ s/^\&//;

    my $sResult= $self->SUPER::get_value($sName);
    $sResult= $self->{CONF}->get_value($sName) unless defined $sResult && $sResult ne '*default*';
    $sResult= $sDefault unless defined $sResult && $sResult ne '*default*';
    $sResult= undef unless defined $sResult && $sResult ne '*default*';
    return  $sResult;
}

sub get_node {
    my $self= shift;
    my $sName= shift;
    $sName=~ s/^\&//;

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

sub infoMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->infoMsg(@sMessage);
}

sub warnMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->warnMsg(@sMessage);
}

sub errorMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->errorMsg(@sMessage);
}

sub logExitError {
    my $self= shift;
    my $iExit=shift || 0;
    my @sMessage= @_;

    $self->logError(@sMessage);
    exit $iExit if $iExit;
}

sub logError {
    my $self= shift;
    my @sMessage= @_;

    $self->{LOG_FILE}->log($self->errorMsg(@sMessage));

    $self->{ERRORCODE}= 9;
}

sub log {
    my $self= shift;
    my @sMessage= @_;

    $self->{LOG_FILE}->log(@sMessage);
}

sub logPretending {
    my $self= shift;
    return unless $self->get_value('switch.pretend');

    $self->log("", "*** Only pretending, no changes are made! ****", "");
}

sub _mail {
    my $self= shift;
    my ($sSubject, @aBody) = @_;

    return 0 unless $self->get_value('email');

    my $oMail = new Mail::Send Subject => $sSubject, To => $self->get_value('email');
    # $msg->cc('user@host');
    my $fh = $oMail->open;
    print $fh join("\n", @aBody);
    $fh->close;

    return 1;
}

sub _mail_log {
    my $self= shift;

    return $self->_mail('Rabak Result', $self->{LOG_FILE}->get_messages());
}

sub _mail_warning {
    my $self= shift;
    my ($sSubject, @aBody) = @_;

    return $self->_mail("RABAK WARNING: $sSubject", @aBody);
}

sub _remove_old {
    my $self= shift;
    my @sBakDir= @_;

    my $iCount= $self->get_value('keep');
    if ($iCount) {
        $self->log("Keeping last $iCount versions");
        splice @sBakDir, 0, $iCount;
        foreach (@sBakDir) {
            $self->log("Removing \"$_\"");
            rmtree($_, $self->{DEBUG}) unless $self->get_value('switch.pretend');
        }
    }
}

# -----------------------------------------------------------------------------
#  ...
# -----------------------------------------------------------------------------

sub get_targetPath {
    my $self= shift;

    unless ($self->{_objTarget}) {
        # target may be path, target object or reference to target object
        my $oTarget= $self->{VALUES}{target};
        $oTarget= $self->get_node($oTarget) unless ref $oTarget;
        if (ref $oTarget) {
            $self->{_objTarget}= RabakLib::Path->new(
                %{$oTarget->{VALUES}}
            );
        }
        else {
            $self->{_objTarget}= RabakLib::Path->new(
                PATH   => $self->{VALUES}{target},
            );
        }
    }
    return $self->{_objTarget};
}

# collect all backup dirs
sub collect_bakdirs {
    my $self= shift;
    my $sSubSetBakDay= shift || 0;

    my $sBakSet= $self->{VALUES}{name};
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
            next unless $sDayDir =~ /\/(\d\d\d\d\-\d\d\-\d\d)[a-z]?([\-_]\d{3})?\.($sBakSet)$/; # [a-z] for backward compatibility
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

# tests if device is mounted and is a valid rabak target
# @param $sMountDevice
#   device to check
# @param $bUnmount
#   unmount the device if its a valid rabak media
# @return
#   hashtable:
#       {CODE} (int):
#           -1: no device specified
#            0: device is not mounted
#            1: device is mounted but no target media
#            2: device is/was mounted and is target media
#       {INFO} (string):
#            explaining information about CODE
#       {ERROR} (string):
#            additional error messages
#       {UMOUNT} (string):
#            result string of umount command (if executed)
sub _mount_check {
    my $self= shift;
    my $sMountDevice= shift || '';
    my $sTargetValue= shift || '';
    my $bUnmount= shift || 0;

    return { CODE => -1 } if !$sMountDevice;

    my $sqTargetValue= quotemeta $sTargetValue;
    if ($self->get_value('switch.targetvalue')) {
        $sTargetValue.= "." . $self->get_value('switch.targetvalue');
        $sqTargetValue= quotemeta $sTargetValue;
    }
    else {
        $sqTargetValue.= '(\.\w+)?';
    }

    my $result= {
        CODE => 0,
    };

    my $oTargetPath= $self->get_targetPath;

    $sMountDevice= $oTargetPath->abs_path($sMountDevice);

    my $sqMountDevice= quotemeta $sMountDevice;

    my $cur_mounts= $oTargetPath->mount;
    # TODO:
    #     check for "mount" outputs different from '/dev/XXX on /mount/dir type ...' on other systems
    #     notice: the check for "type" after mount dir is because of missing delimiters if mount dir contains spaces!
    if ($cur_mounts =~ /^$sqMountDevice\son\s+(\/.*)\stype\s/m) {
        my $sMountDir= $1;

        $result->{CODE}= 1; # defaults to "not a target"

        my $sDevConfFile= File::Spec->join($sMountDir, $self->get_value('switch.dev_conf_file') || "rabak.dev.cf");
        if ($oTargetPath->isReadable("$sDevConfFile")) {
            if ($sTargetValue) {
                my $oDevConfFile= RabakLib::ConfFile->new($oTargetPath->getLocalFile($sDevConfFile));
                my $oDevConf= $oDevConfFile->conf();
                my $sFoundTargets = $oDevConf->get_value('targetvalues') || '';
                if (" $sFoundTargets " =~ /\s$sqTargetValue\s/) {
                    $result->{CODE}= 2;
                    $result->{INFO}= "Target value \"$sTargetValue\" found on device \"$sMountDevice\"";
                }
                else {
                    $result->{INFO}= "Target value \"$sTargetValue\" not found on device \"$sMountDevice\" (found: \"" .
                        join("\", \"", split(/\s+/, $sFoundTargets)) .
                        "\")";
                }
            }
            else { # no target group specified -> if conf file is present, this is our target
                $result->{CODE}= 2;
                $result->{INFO}= "No target group specified";
            }
        }
        else {
            $result->{INFO}= "Device config file \"".$oTargetPath->getFullPath($sDevConfFile)."\" not found on device \"$sMountDevice\"";
        }

        $result->{UMOUNT}= $oTargetPath->umount("$sMountDevice 2>&1") if ($result->{CODE} == 2) && $bUnmount;
    }
    return $result;
}

# @param $oMount
#       A RakakConf object containing the mount point information
# @param $arMessage
#       A ref to an array, in which _mount stores warnings and messages
# @param $arUnmount
#       A ref to an array, in which _mount stores the mount points that need unmounting
# @param $arAllMount
#       A ref to an array, in which _mount stores all mount points
# return
#       0: failed
#       1: succeeded
sub _mount {
    my $self= shift;
    my $oMount= shift;
    my $bIsTarget= shift;
    my $arMessage = shift || {};
    my $arUnmount= shift || {};
    my $arAllMount= shift || {};

    my $sMountDeviceList= $oMount->{VALUES}{device} || '';
    my $sMountDir= $oMount->{VALUES}{directory} || '';
    my $sTargetGroup= $self->get_targetPath->get_value("group");
    my $sMountType= $oMount->{VALUES}{type} || '';
    my $sMountOpts= $oMount->{VALUES}{opts} || '';
    my $sUnmount= "";

    # backward compatibility
    if (!$bIsTarget && $oMount->{VALUES}{istarget}) {
        push @{ $arMessage }, $self->warnMsg("Mount option \"istarget\" is depricated",
            "Please use \"mount\" in Target Objects! (see Doc)");
        $bIsTarget= 1;
    }
    # backward compatibility
    $sTargetGroup= $self->{VALUES}{targetgroup} if !$sTargetGroup && $self->{VALUES}{targetgroup};


    # parameters for mount command
    my $spMountDevice= ""; # set later
    my $spMountDir=    $sMountDir    ? " \"$sMountDir\""     : "";
    my $spMountType =  $sMountType   ? " -t \"$sMountType\"" : "";
    my $spMountOpts =  $sMountOpts   ? " -o\"$sMountOpts\""  : "";

    my %checkResult;
    my $iResult= !$bIsTarget; # for targets default to "failed", for other mounts only warnings are raised

    my @sMountDevices= ();

#    push @{ $arMessage }, $self->infoMsg("Trying to mount \"" .
#        join("\", \"", split(/\s+/, $sMountDeviceList)) . "\"");

    for my $sMountDevice (split(/\s+/, $sMountDeviceList)) {
        push @sMountDevices, glob($sMountDevice);
    }

    # if no device were given, try mounting by mount point
    push @sMountDevices, '' if $#sMountDevices < 0;

    my @sMountMessage = ();
    for my $sMountDevice (@sMountDevices) {
        my @sCurrentMountMessage = ();
        $sUnmount= $sMountDevice ne '' ? $sMountDevice : $sMountDir;
        $spMountDevice= $sMountDevice ? " \"$sMountDevice\""  : "";
        push @sCurrentMountMessage, $self->infoMsg("Trying to mount \"$sUnmount\"");

        # if device is target, check if its already mounted.
        # if mounted, check if it's our target (and unmount if it is)
        if ($bIsTarget) {
            unless ($sMountDevice) {
                push @sCurrentMountMessage, $self->warnMsg("Target devices have to be specified with device name");
                goto nextDevice;
            }
            %checkResult = %{ $self->_mount_check($sMountDevice, $sTargetGroup, 1) };
            push @sCurrentMountMessage, $self->infoMsg($checkResult{INFO}) if $checkResult{INFO};
            push @sCurrentMountMessage, $self->errMsg($checkResult{ERROR}) if $checkResult{ERROR};
            if ($checkResult{CODE} == 1) {
                goto nextDevice;
            }
            if ($checkResult{CODE} == 2) {
                push @sCurrentMountMessage, $self->warnMsg("Device $sMountDevice was already mounted");
                push @sCurrentMountMessage, $self->warnMsg("Umount result: \"${checkResult{UMOUNT}}\"") if $checkResult{UMOUNT};
            }
        }

        my $oPath= $bIsTarget ? $self->get_targetPath : RabakLib::Path->new();
        my $sMountResult= $oPath->mount("$spMountType$spMountDevice$spMountDir$spMountOpts 2>&1");
        if ($?) { # mount failed
            chomp $sMountResult;
            $sMountResult =~ s/\r?\n/ - /g;
            push @sCurrentMountMessage, $self->warnMsg("Mounting$spMountDevice$spMountDir failed with: $sMountResult!");
            goto nextDevice;
        }

        if ($bIsTarget) { # this mount object is a target -> check for right target device
            %checkResult = %{ $self->_mount_check($sMountDevice, $sTargetGroup, 0) };
            push @sCurrentMountMessage, $self->infoMsg($checkResult{INFO}) if $checkResult{INFO};
            push @sCurrentMountMessage, $self->errMsg($checkResult{ERROR}) if $checkResult{ERROR};
            if ($checkResult{CODE} == 0) { # device is not mounted
                push @sCurrentMountMessage, $self->warnMsg("Device \"$sMountDevice\" is not mounted!");
            }
            elsif ($checkResult{CODE} == 1) { # device is no valid target
                $sMountResult= $oPath->umount("$sUnmount 2>&1");
                if ($?) { # umount failed
                    chomp $sMountResult;
                    $sMountResult =~ s/\r?\n/ - /g;
                    push @sCurrentMountMessage, $self->warnMsg("Unmounting \"$sUnmount\" failed with: $sMountResult!");
                }
                else {
                    push @sCurrentMountMessage, $self->infoMsg("Unmounted \"$sUnmount\"");
                }
            }
            elsif ($checkResult{CODE} == 2) { #
                $iResult= 1;
                @sMountMessage= (); # drop old mount messages if this one succeeded
            }
        }
        else { # this mount object is no target -> everything is fine
            $iResult= 1;
            @sMountMessage= (); # drop old mount messages if this one succeeded
        }
nextDevice:
        push @sMountMessage, @sCurrentMountMessage;
        last if $iResult;
    }
    push @{ $arMessage }, @sMountMessage;

    if ($sUnmount) {
        push @{ $arAllMount }, $sUnmount;

        $sUnmount= "\@$sUnmount" if $bIsTarget; # mark targets to use $oTargetPath for unmounting
        # We want to unmount in reverse order:
        unshift @{ $arUnmount }, $sUnmount if $oMount->{VALUES}{unmount} && $iResult;
    }

    push @{ $arMessage }, $self->infoMsg("Mounted$spMountDevice$spMountDir") if $iResult;
    push @{ $arMessage }, $self->errorMsg("All mounts failed") unless $iResult;
    return $iResult;
}

sub _mkdir {
    my $self= shift;
    my $sDir= shift;

    return 1 if $self->get_value('switch.pretend');

    # TODO: set MASK ?
    return 1 if $self->{_objTarget}->mkdir($sDir);

    $self->log($self->warnMsg("Mkdir '$sDir' failed: $!"));
    return 0;
}

# -----------------------------------------------------------------------------
#  Mount & Unmount
# -----------------------------------------------------------------------------

# return
#       0: failed
#       1: succeeded
sub mount {
    my $self= shift;
    my $arMessage= shift || {};

    # Collect all mount errors, we want to output them later
    my $arUnmount= $self->{_UNMOUNT_LIST} || [];
    my $arAllMount= $self->{_ALL_MOUNT_LIST} || [];

    if ($self->{VALUES}{targetgroup}) {
        push @{ $arMessage }, $self->warnMsg("BakSet option \"targetgroup\" is depricated",
            "Please use \"group\" in Target Objects! (see Doc)")
    }

    my @sToMount= ({MOUNT => $self->{VALUES}{mount}});
    my $oTarget= $self->{VALUES}{target};
    $oTarget= $self->get_node($oTarget) unless ref $oTarget;
    push @sToMount, {
        MOUNT => $oTarget->{VALUES}->{mount},
        TARGET => 1,
    } if ref $oTarget &&  $oTarget->{VALUES}->{mount};

    my $iResult= 1; # defaults to mount succeeded

    for my $hMount (@sToMount) {
        my $sMount= $hMount->{MOUNT};
        my $bIsTarget = $hMount->{TARGET};
        last unless $iResult;

        if ($sMount) {

            # If the 'mount' setting is a node, then just do one mount:
            if (ref $sMount) {
                $iResult = $self->_mount($sMount, $bIsTarget, $arMessage, $arUnmount, $arAllMount);
            }
            else {
                for my $sToken (split(/\s+/, $sMount)) {
                    my $oMount= $self->get_node($sToken);
                    if (!ref $oMount) {
                        push @{ $arMessage }, $self->warnMsg("Mount information \"$sToken\" not defined in config file");
                        next;
                    }
                    $iResult= $self->_mount($oMount, $bIsTarget, $arMessage, $arUnmount, $arAllMount);
                    if (!$iResult && $bIsTarget) { # on targets mount failures are fatal -> exit
                        $iResult= 0;
                        last;
                    }
                }
            }
        }
    }

    $self->{_UNMOUNT_LIST}= $arUnmount;
    $self->{_ALL_MOUNT_LIST}= $arAllMount;

    return $iResult;
}

sub get_mounts {
    my $self= shift;

    return $self->{_UNMOUNT_LIST} || [];
}

sub unmount {
    my $self= shift;
    my $bBlaimLogFile= shift || 0;

    my @sAllMount= @{ $self->{_ALL_MOUNT_LIST} };
    my @sUnmount= @{ $self->{_UNMOUNT_LIST} };

    my %sAllMount;
    map { $sAllMount{$_}= 1; } @sAllMount;
    my @sUnmount2= ();

    for (@sUnmount) {
        my $sUnmount2= $_;
        my $oPath;
        if (s/^\@//) { # is target mount
            $oPath= $self->get_targetPath;
            if ($bBlaimLogFile) { # do not unmount targets while log file is open
                push @sUnmount2, $sUnmount2;
                next;
            }
        }
        else {
            $oPath= RabakLib::Path->new;
        }
        my $sResult= $oPath->umount("\"$_\" 2>&1");
        if ($?) {
            chomp $sResult;
            $sResult =~ s/\r?\n/ - /g;
            next unless $sAllMount{$_};
            $self->log($self->warnMsg("Unmounting \"$_\" failed: $sResult!"));
            $self->log($self->warnMsg("(Maybe because of the log file. Retrying after log file was closed)")) if $bBlaimLogFile;
            push @sUnmount2, $sUnmount2;
            next;
        }
        $self->log("Unmounted \"$_\"");
    }

    $self->{_UNMOUNT_LIST}= \@sUnmount2;
}

# -----------------------------------------------------------------------------
#  Backup
# -----------------------------------------------------------------------------

sub backup {
    my $self= shift;

    my $iResult= 0;

    if ($self->backup_setup() == 0) {
        $iResult= $self->backup_run();
    }
    $self->backup_cleanup();

    return $iResult;
}

sub backup_setup {
    my $self= shift;

    my $sSubSet= "";
    my @sBakDir= ();

    $self->log($self->infoMsg("Rabak Version " . $self->{VERSION}));
    $self->logPretending();

    my @sMountMessage;
    my $iMountResult= $self->mount(\@sMountMessage, 1);

    # my @sMountMessage= @{ $self->{_MOUNT_MESSAGE_LIST} };

    my @sAllMount= @{ $self->{_ALL_MOUNT_LIST} };
    my @sUnmount= @{ $self->{_UNMOUNT_LIST} };

    unless ($iMountResult) { # fatal mount error
        $self->logError("There was at least one fatal mount error. Backup set skipped.");
        $self->logError(@sMountMessage);
        return 3;
    }

    if (scalar @sMountMessage) {
        $self->log("All mounts completed. More information after log file initialization...");
    }

    my $oTargetPath= $self->get_targetPath();

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

    my $sBakMonth= strftime("%Y-%m", localtime);
    my $sBakDay= strftime("%Y-%m-%d", localtime);
    my $sBakSet= $self->{VALUES}{name};

    my $sLogFile= "$sBakMonth-log/$sBakDay.$sBakSet.log";

    $self->_mkdir("$sBakMonth.$sBakSet");

    if (!$self->get_value('switch.pretend') && $self->get_value('switch.logging')) {
        $self->_mkdir("$sBakMonth-log");

        my $sLogLink= "$sBakMonth.$sBakSet/$sBakDay.$sBakSet.log";

        my $sLogFileName= $oTargetPath->get_value("PATH") . "/$sLogFile";

        my $sError= $self->{LOG_FILE}->open($sLogFileName, $oTargetPath);
        if ($sError) {
            $self->log($self->warnMsg("Can't open log file \"$sLogFileName\" ($sError). Going on without..."));
        }
        else {
            if (!$self->{LOG_FILE}->is_new()) {

                # TODO: only to file
                $self->log("", "===========================================================================", "");
            }
            $oTargetPath->symlink("../$sLogFile", "$sLogLink");
            $oTargetPath->unlink("current-log.$sBakSet");
            $oTargetPath->symlink($sLogFile, "current-log.$sBakSet");
        }
    }

    ($sSubSet, @sBakDir)= $self->collect_bakdirs($sBakDay);

    $self->{VALUES}{unique_target}= "$sBakDay$sSubSet.$sBakSet";
    my $sTarget= "$sBakMonth.$sBakSet/" . $self->{VALUES}{unique_target};
    $self->{VALUES}{full_target}= $oTargetPath->getPath . "/$sTarget";
    # $self->{VALUES}{bak_dirs}= \@sBakDir;

    $self->_mkdir($sTarget);

    $self->log($self->infoMsg("Backup $sBakDay exists, using subset.")) if $sSubSet;
    $self->log($self->infoMsg("Backup start at " . strftime("%F %X", localtime) . ": $sBakSet, $sBakDay$sSubSet, " . $self->{VALUES}{title}));
    $self->log("Logging to: ".$oTargetPath->getFullPath."/$sLogFile") if $self->get_value('switch.pretend') && $self->get_value('switch.logging');
    $self->log("Source: " . $self->{VALUES}{type} . ":" . $self->{VALUES}{source});

    $self->log(@sMountMessage);

    $self->{_BAK_DIR_LIST}= \@sBakDir;
    $self->{_BAK_DAY}= $sBakDay;
    $self->{_BAK_SET}= $sBakSet;
    $self->{_SUB_SET}= $sSubSet;
    $self->{_TARGET}= $sTarget;

    return 0;
}

sub backup_run {
    my $self= shift;

    my $sBakType= $self->{VALUES}{type};

    my @sBakDir= @{ $self->{_BAK_DIR_LIST} };
    my $oTargetPath= $self->get_targetPath;
    my $sBakSet= $self->{_BAK_SET};
    my $sTarget= $self->{_TARGET};

    my $iErrorCode= 0;
    eval {
        require "RabakLib/Type/" . ucfirst($sBakType) . ".pm";
        my $sClass= "RabakLib::Type::" . ucfirst($sBakType);
        my $oBackup= $sClass->new($self);
        $self->{LOG_FILE}->set_prefix($sBakType);
        $iErrorCode= $oBackup->run(@sBakDir);
        $self->{LOG_FILE}->set_prefix();
    };

    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            $self->logError("ERROR! Backup type \"" . $sBakType . "\" is not defined: $@");
        }
        else {
            $self->logError("ERROR! An error occured: $@");
        }
        $iErrorCode= 9;
    }
    elsif (!$iErrorCode) {
        $self->log("Done!");
    }

    $self->_remove_old(@sBakDir) unless $iErrorCode;    # only remove old if backup was done

    unless ($self->get_value('switch.pretend')) {
        $oTargetPath->unlink("current.$sBakSet");
        $oTargetPath->symlink("$sTarget", "current.$sBakSet");
    }

    # check for disc space
    my $sSpaceThreshold= $self->get_value('target_discfree_threshold') || '';
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

    $self->unmount(1);

    # $self->logError(@sMountMessage);

    my $oTargetPath= $self->get_targetPath;
    my $sBakSet= $self->{_BAK_SET};
    my $sBakDay= $self->{_BAK_DAY};
    my $sSubSet= $self->{_SUB_SET};

    $self->log($self->infoMsg("Backup done at " . strftime("%F %X", localtime) . ": $sBakSet, $sBakDay$sSubSet")) if $sBakSet && $sBakDay && $sSubSet;
    $self->{LOG_FILE}->close();
    $self->unmount(0);

    $self->_mail_log();
}

# -----------------------------------------------------------------------------
#  Remove file
# -----------------------------------------------------------------------------

use File::Path;

sub rm_file {

    die "The current rm_file is flawed. It will be available again in the next release!";

    my $self= shift;
    my @sFileMask= shift || ();

    # print Dumper(\@sFileMask);

    map { $self->logExitError(2, "Every filemask MUST start with \"/\"!") unless /^\//; } @sFileMask;

    return 2 unless scalar @sFileMask && defined $sFileMask[0];

    $self->logPretending();

    my %aDirs= ();
    my %aFiles= ();
    my %iFoundMask= ();

    my $sBakSet= $self->{VALUES}{name};
    my $oTargetPath= $self->get_targetPath();

    # TODO: Make a better check!
    $self->logExitError(3, "Can't remove! \"$sBakSet.target\" is empty or points to file system root.") if $oTargetPath->getPath eq '' || $oTargetPath->getPath eq '/';

    my @sBakDir= $self->collect_bakdirs();

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
        !$self->get_value('switch.pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        $self->log("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->get_value('switch.pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { $self->log("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
