#!/usr/bin/perl

package RabakLib::Set;

use warnings;
use strict;

use RabakLib::Conf;
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
    $self->{NAME}= $sName;
    $self->{LOGFILE}= undef;
    $self->{LOG}= ();
    $self->{LOGPREFIX}= '';

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

    return "Required value \"" . $self->{VALUES}{name} . ".$sField\" missing." unless defined $self->{VALUES}{$sField} && !ref $self->{VALUES}{$sField};
    return undef;
}

sub _validate {
    my $self= shift;

    return $self->_need_value('title') || $self->_need_value('source') || $self->_need_value('target');
}

sub get_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;

    my $sResult= $self->SUPER::get_value($sName);
    $sResult= $self->{CONF}->get_value($sName) unless defined $sResult && $sResult ne '*default*';
    $sResult= $sDefault unless defined $sResult && $sResult ne '*default*';
    $sResult= undef unless defined $sResult && $sResult ne '*default*';
    return  $sResult;
}

sub get_node {
    my $self= shift;
    my $sName= shift;

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

sub xerror {
    my $self= shift;
    my $sMessage= shift;
    my $iExit= shift || 0;

    $self->xlog($sMessage);

    exit $iExit if $iExit;
    $self->{ERRORCODE}= 9;
}

sub xlog {
    my $self= shift;
    my $sMessage= shift;
    my $iLevel= shift || 0;

    # our $fwLog;
    return if $self->get_value('switch.quiet');

    push @{ $self->{LOG} }, $sMessage;

    $sMessage= $self->{LOGPREFIX} . $sMessage;

    print "# $sMessage\n";
    return unless $self->{LOGFILE} && $self->get_value('switch.logging') && !$self->get_value('switch.pretend');

    my $fwLog= $self->{LOGFILE};
    my $sName= $self->get_value('name');
    print $fwLog _timestr() . "\t$sName\t$sMessage\n";
}

sub xlog_pretending {
    my $self= shift;
    return unless $self->get_value('switch.pretend');

    $self->xlog("");
    $self->xlog("*** Only pretending, no changes are made! ****");
    $self->xlog("");
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

    return $self->_mail('Rabak Result', @{ $self->{LOG} });
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
        $self->xlog("Keeping last $iCount versions");
        splice @sBakDir, 0, $iCount;
        foreach (@sBakDir) {
            $self->xlog("Removing \"$_\"");
            rmtree($_, $self->{DEBUG}) unless $self->get_value('switch.pretend');
        }
    }
}

# -----------------------------------------------------------------------------
#  ...
# -----------------------------------------------------------------------------

sub get_bakset_target {
    my $self= shift;
    return File::Spec->rel2abs($self->{VALUES}{target});
}

sub collect_bakdirs {
    my $self= shift;
    my $sSubSetBakDay= shift || 0;

    my $sBakSet= $self->{VALUES}{name};
    my $sBakDir= get_bakset_target($self);
    my @sBakDir= ();
    my $sSubSet= '';

    while (<$sBakDir/*>) {
        next unless /^$sBakDir\/(.*)/;
        my $sMonthDir= $1;

        next unless -d "$sBakDir/$sMonthDir" && $sMonthDir =~ /^(\d\d\d\d\-\d\d)\.($sBakSet)$/;

        while (<$sBakDir/$sMonthDir/*>) {
            next unless /^$sBakDir\/$sMonthDir\/(.*)/;
            my $sDayDir= $1;
            # print "$sDayDir??\n";
            next unless -d $_ && $sDayDir =~ /^(\d\d\d\d\-\d\d\-\d\d)([a-z])?\.($sBakSet)$/;
            if ($sSubSetBakDay eq $1) {
                die "Maximum of 27 backups reached!" if $2 && $2 eq 'z';
                if (!$2) {
                    $sSubSet= 'a' if $sSubSet eq '';
                }
                else {
                    $sSubSet= chr(ord($2)+1) if $sSubSet le $2;
                }
            }
            push @sBakDir, "$sBakDir/$sMonthDir/$sDayDir";
            # print "$sDayDir\n";
        }
    }

    @sBakDir= sort { $b cmp $a } @sBakDir;

    unshift @sBakDir, $sSubSet if $sSubSetBakDay;

    return @sBakDir;
}

# -----------------------------------------------------------------------------
#  Backup
# -----------------------------------------------------------------------------

# @param $oMount
# 	A RakakConf object containing the mount point information
# @param $arUnmount
#	A ref to an array, in which _mount stores the mount points that need unmounting
# @param $arAllMount
#	A ref to an array, in which _mount stores all mount points
sub _mount {
    my $self= shift;
    my $oMount= shift;
    my $arUnmount= shift;
    my $arAllMount= shift;

    my @aResult= ();
    my $sMountDevice= $oMount->{VALUES}{device} || '';
    my $sMountDir= $oMount->{VALUES}{directory} || '';
    my $bTestTargetId= $oMount->{VALUES}{istarget} || '';
    my $sMountType= $oMount->{VALUES}{type} || '';
    my $sMountOpts= $oMount->{VALUES}{opts} || '';
    my $sUnmount= $sMountDevice ne '' ? $sMountDevice : $sMountDir;

    $sMountDevice= " \"$sMountDevice\"" if $sMountDevice;
    $sMountDir= " \"$sMountDir\"" if $sMountDir;
    $sMountType = " -t \"$sMountType\"" if $sMountType;
    $sMountOpts = " -o\"$sMountOpts\"" if $sMountOpts;

    # First unmount the device, it may be pointing to a wrong mount point.
    # Mount would fail and terrible things could happen.
    `umount $sUnmount 2>&1`;

    push @{ $arAllMount }, $sUnmount;

    my $sResult= `mount $sMountType$sMountDevice$sMountDir$sMountOpts 2>&1`;
    if ($?) {
	chomp $sResult;
	$sResult =~ s/\r?\n/ - /g;
        return "WARNING! Mounting$sMountDevice$sMountDir failed with: $sResult!";
    }

    my $sTargetInfo= "";

    if ($bTestTargetId && $self->{VALUES}{targetgroup}) {
	my $sTargetIdName= get_bakset_target($self) . "/" . $self->{VALUES}{targetgroup} . ".ids";
	my $bWrongTarget= !-r $sTargetIdName;
	my $sTargetIds= 'file does not exist';
	my $sExpectedTargetId = $self->get_value('switch.targetid') || '';
	if (!$bWrongTarget && $sExpectedTargetId) {
	    $sTargetIds= `cat "$sTargetIdName"`;
	    my $sQuotExpectedTargetId = quotemeta $sExpectedTargetId;
	    $bWrongTarget= "\n$sTargetIds\n" !~ /\n$sQuotExpectedTargetId\r?\n/;
	}
	if ($bWrongTarget) {
	    $sTargetIds= join("', '", split(/\r?\n/, $sTargetIds));
	    my $sError= "WARNING! Mount point$sMountDevice$sMountDir has wrong targetgroup value (expected '$sExpectedTargetId' but got '$sTargetIds')";
	    $sResult= `umount $sUnmount 2>&1`;
	    if ($?) {
		chomp $sResult;
		$sResult =~ s/\r?\n/ - /g;
	        return "$sError\n# WARNING! Unmounting \"$sUnmount\" failed with: $sResult!";
	    }
	    return "$sError\n# Unmounted \"$sUnmount\"";
	}
        $sTargetInfo= "Found desired value \"" . $sExpectedTargetId . "\" for targetgroup \"" . $self->{VALUES}{targetgroup} . "\"\n# ";
    }

    # We want to unmount in reverse order:
    unshift @{ $arUnmount }, $sUnmount if $oMount->{VALUES}{unmount};

    return $sTargetInfo . "Mounted$sMountDevice$sMountDir";
}

sub _mkdir {
    my $self= shift;
    my $sDir= shift;

    return 1 if $self->get_value('switch.pretend');

    # TODO: set MASK ?
    return 1 if mkdir $sDir;

    return 1 if $! == 17; # file exists is ok

    $self->xerror("WARNING! Mkdir '$sDir' failed: $!");
    return 0;
}

sub backup {
    my $self= shift;

    my $iErrorCode= 0;
    my $sBakSet= $self->{VALUES}{name};
    my $sSourceDir= $self->{VALUES}{source};
    my $sBakType= $self->{VALUES}{type};
    my $sBakDir= get_bakset_target($self);
    my $sBakMonth= strftime("%Y-%m", localtime);
    my $sBakDay= strftime("%Y-%m-%d", localtime);
    my $sSubSet= "";
    my @sBakDir= ();

    $self->xlog_pretending();

    # Collect all mount errors, we want to output them later
    my @sMountError= ();
    my @sFirstOfMountError= ();
    my @sUnmount= ();
    my @sWarnOnUnmount= ();

    if ($self->{VALUES}{mount}) {

	# If the 'mount' setting is a node, then just do one mount:
        if (ref $self->{VALUES}{mount}) {
	    push @sMountError, $self->_mount($self->{VALUES}{mount}, \@sUnmount, \@sWarnOnUnmount);
        }
        else {
	
	    # Else it's a string containing a list of node names. Try to mount them all.
	    # If the sequence "firstof mp1 mp2 mp3 ;" is found, try to mount the first
	    # possible one. We need that if we want to mount a USB device which hasn't got
	    # a fixed name.
            my $iFirstOf= 0;
            for my $sToken (split(/\s+/, $self->{VALUES}{mount})) {
                if ($iFirstOf == 0 && $sToken eq 'firstof') {
                    $iFirstOf= 1;
                    next;
                }
                if ($iFirstOf && $sToken eq ';') {
		    if ($iFirstOf != 2) {
			push @sMountError, "WARNING! None of the \"firstof\" mount points could be mounted. Results:";
    			push @sMountError, @sFirstOfMountError;
			push @sMountError, "WARNING! -- SNIP --";
		    }
		    else {
			# Don't give a warning on failing unmounts if mount point is one of 'firstof' and
			# there was a succesful mount. This removes the failed unmounts from @sWarnOnUnmount:
			splice @sWarnOnUnmount, $#sWarnOnUnmount - $#sFirstOfMountError - 1, $#sFirstOfMountError + 1;
		    }
                    $iFirstOf= 0;
		    @sFirstOfMountError= ();
                    next;
                }
		next if $iFirstOf == 2;
                my $oMount= $self->get_node($sToken);
                if (!ref $oMount) {
                    push @sMountError, "WARNING! Mount information \"$sToken\" not defined in config file";
		    next;
                }
		my $sResult= $self->_mount($oMount, \@sUnmount, \@sWarnOnUnmount);
		if ($iFirstOf) {
		    if ($sResult =~ /^WARNING/) {
    			push @sFirstOfMountError, $sResult;
			next;
		    }
		    $iFirstOf= 2;
		}
		push @sMountError, $sResult;
            }
        }

        $self->xlog("All mounts completed. More information after log file initialization...");
    }

    # map { $self->xerror($_); } @sMountError; print Dumper(@sWarnOnUnmount); goto BACKUP_FAILED;
    
    if (!-d $sBakDir) {
        $self->xerror("Target \"$sBakDir\" is not a directory. Backup set skipped.");
        goto BACKUP_FAILED;
    }
    if (!-w $sBakDir) {
        $self->xerror("Target \"$sBakDir\" is not writable. Backup set skipped.");
        goto BACKUP_FAILED;
    }

    # our $fwLog;

    my $sLogFile= "$sBakMonth-log/$sBakDay.$sBakSet.log";

    $self->_mkdir("$sBakDir/$sBakMonth.$sBakSet");

    if (!$self->get_value('switch.pretend') && $self->get_value('switch.logging')) {
        $self->_mkdir("$sBakDir/$sBakMonth-log");

        my $sLogLink= "$sBakMonth.$sBakSet/$sBakDay.$sBakSet.log";

        my $bExists= -f "$sBakDir/$sLogFile";
        if (open ($self->{LOGFILE}, ">>$sBakDir/$sLogFile")) {
            if ($bExists) {

                # TODO: only to file
                $self->xlog("");
                $self->xlog("===========================================================================");
                $self->xlog("");
            }
            symlink "../$sLogFile", "$sBakDir/$sLogLink";
        }
        else {
            undef $self->{LOGFILE};
            $self->set_value('switch.logging', 0);
            $self->xerror("WARNING! Can't open log file \"$sBakDir/$sLogFile\" ($!). Going on without...");
        }
    }

    ($sSubSet, @sBakDir)= $self->collect_bakdirs($sBakDay);

    $self->{VALUES}{unique_target}= "$sBakDay$sSubSet.$sBakSet";
    my $sTarget= "$sBakMonth.$sBakSet/" . $self->{VALUES}{unique_target};
    $self->{VALUES}{full_target}= "$sBakDir/$sTarget";
    # $self->{VALUES}{bak_dirs}= \@sBakDir;

    $self->_mkdir($self->{VALUES}{full_target});

    $self->xlog("Backup $sBakDay exists, using subset.") if $sSubSet;
    $self->xlog("Backup start at " . strftime("%F %X", localtime) . ": $sBakSet, $sBakDay$sSubSet, " . $self->{VALUES}{title});
    $self->xlog("Logging to: $sBakDir/$sLogFile") if $self->get_value('switch.logging');
    $self->xlog("Source: " . $self->{VALUES}{type} . ":" . $self->{VALUES}{source});

    map { $self->xerror($_); } @sMountError;

    eval {

        # IMPORTANT TODO: use "use" or "do" or "require"!

        require "RabakLib/Type/" . ucfirst($sBakType) . ".pm";
        my $sClass= "RabakLib::Type::" . ucfirst($sBakType);
        my $oBackup= $sClass->new($self);
        $self->{LOGPREFIX}= "[$sBakType] ";
        $iErrorCode= $oBackup->run(@sBakDir);
        $self->{LOGPREFIX}= "";
    };

    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            $self->xerror("ERROR! Backup type \"" . $sBakType . "\" is not defined: $@");
        }
        else {
            $self->xerror("ERROR! An error occured: $@");
        }
        $iErrorCode= 9;
    }
    elsif (!$iErrorCode) {
        $self->xlog("Done!");
    }

    $self->_remove_old(@sBakDir) unless $iErrorCode;    # only remove old if backup was done

    unless ($self->get_value('switch.pretend')) {
        unlink "$sBakDir/current.$sBakSet";
        symlink "$sTarget", "$sBakDir/current.$sBakSet";
        unlink "$sBakDir/current-log.$sBakSet";
        symlink "$sLogFile", "$sBakDir/current-log.$sBakSet";
    }

    # check for disc space
    my $space_threshold = $self->get_value('target_discfree_threshold') || '';
    if ($space_threshold) {
        my $st_value = $1 if $space_threshold =~ /\b([\d\.]+)/;
        my $st_unit = 'K';
        $st_unit = uc($1) if $space_threshold =~ /$st_value\s*([gmkb\%])/i;
        my $df = (split /\n/, `df -k "$sBakDir"`)[1];
        my ($df_size, $df_avail) = ($1, $2) if $df =~ /^\S+\s+(\d+)\s+\d+\s+(\d+)\s+/;
        $df_avail /= $df_size / 100 if $st_unit eq '%';
        $df_avail >>= 20            if $st_unit eq 'G';
        $df_avail >>= 10            if $st_unit eq 'M';
        $df_avail <<= 10            if $st_unit eq 'B';
        if ($st_value > $df_avail) {
            $self->_mail_warning('disc space too low',
                (
                    "The free space on your target \"$sBakDir\" has dropped",
                    "below $st_value$st_unit to $df_avail$st_unit."
                )
            );
        }
    }

BACKUP_FAILED:

    # map { $self->xerror($_); } @sMountError;

    my %sWarnOnUnmount;
    map { $sWarnOnUnmount{$_}= 1; } @sWarnOnUnmount;
    my @sUnmount2= ();

    for (@sUnmount) {
        my $sResult= `umount "$_" 2>&1`;
        if ($?) {
	    chomp $sResult;
    	    $sResult =~ s/\r?\n/ - /g;
	    next unless $sWarnOnUnmount{$_};
    	    $self->xerror("WARNING! Unmounting \"$_\" failed: $sResult!");
    	    $self->xerror("WARNING! (Maybe because of the log file. Retrying after log file was closed)");
	    push @sUnmount2, $_;
	    next;
	}
        $self->xlog("Unmounted \"$_\"");
    }

    $self->xlog("Backup done at " . strftime("%F %X", localtime) . ": $sBakSet, $sBakDay$sSubSet");


    # ATTENTION! QUICK HACK!
    # TODO: Can't unmount if log file is open

    close $self->{LOGFILE} if defined $self->{LOGFILE};
    $self->{LOGFILE}= undef;

    for (@sUnmount2) {
        my $sResult= `umount "$_" 2>&1`;
        if ($?) {
	    chomp $sResult;
    	    $sResult =~ s/\r?\n/ - /g;
	    next unless $sWarnOnUnmount{$_};
    	    $self->xerror("WARNING! Unmounting \"$_\" failed: $sResult!");
	    next;
	}
        $self->xlog("Unmounted \"$_\"");
    }

    # -- SNIP --


    $self->_mail_log();

    return $iErrorCode;
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

    map { $self->xerror("Every filemask MUST start with \"/\"!", 2) unless /^\//; } @sFileMask;

    return 2 unless scalar @sFileMask && defined $sFileMask[0];

    $self->xlog_pretending();

    my %aDirs= ();
    my %aFiles= ();
    my %iFoundMask= ();

    my $sBakSet= $self->{VALUES}{name};
    my $sBakDir= $self->get_bakset_target($self);

    # TODO: Make a better check!
    $self->xerror("Can't remove! \"$sBakSet.target\" is empty or points to file system root.", 3) if $sBakDir eq '' || $sBakDir eq '/';

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
        $self->xlog("Removing " . scalar @{ $aDirs{$_} } . " directories: $_");
        !$self->get_value('switch.pretend') && rmtree($aDirs{$_}, $self->{DEBUG});

        # print Dumper($aDirs{$_});

    } sort { $a cmp $b } keys %aDirs;

    map {
        $self->xlog("Removing " . scalar @{ $aFiles{$_} } . " files: $_");

        # print Dumper($aFiles{$_});

        !$self->get_value('switch.pretend') && unlink(@{ $aFiles{$_} });
    } sort { $a cmp $b } keys %aFiles;

    map { $self->xlog("Didn't find: $_") unless defined $iFoundMask{$_} } @sFileMask;

    return 0;
}

1;
