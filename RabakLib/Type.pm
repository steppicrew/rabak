#!/usr/bin/perl

package RabakLib::Type;

use warnings;
use strict;

#use File::Temp ();
use RabakLib::Path;

# use Rabak::ConfFile;

# use vars qw(@ISA);

sub new {
    my $class = shift;
    my $oSet= shift;
    my $self= {
        ERRORCODE => 0,
        DEBUG => 0,
        SET => $oSet,
    };
    bless $self, $class;
}

sub get_targetPath {
    my $self= shift;
    return $self->{SET}->get_targetPath;
#    return File::Spec->rel2abs($self->get_value('target'));
}

sub collect_bakdirs {
    my $self= shift;
    my $sSubSetBakDay= shift || 0;

    my $sBakSet= $self->get_value('name');
    my $sBakDir= $self->get_bakset_target();
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
    # return wantarray ? (\$sBakDir, $sSubSet) : \$sBakDir;
}

sub get_value {
    my $self= shift;
    return $self->{SET}->get_value(@_);
}

sub infoMsg {
    my $self= shift;
    return $self->{SET}->infoMsg(@_);
}

sub warnMsg {
    my $self= shift;
    return $self->{SET}->warnMsg(@_);
}

sub errorMsg {
    my $self= shift;
    return $self->{SET}->errorMsg(@_);
}

sub logError {
    my $self= shift;
    return $self->{SET}->logError(@_);
}

sub log {
    my $self= shift;
    return $self->{SET}->log(@_);
}

sub tempfile {
    return RabakLib::Path->tempfile();
}

sub valid_source_dir {
    my $self= shift;

    my $sSourceDir= $self->get_value('source');
    unless ($sSourceDir =~ /^(\S+\@)?[\-0-9a-z\.]+\:/i) { # if no remote path
        $sSourceDir= File::Spec->rel2abs($sSourceDir);

        if (!-d $sSourceDir) {
            $self->logError("Source \"$sSourceDir\" is not a directory. Backup set skipped.");
            return undef;
        }
        if (!-r $sSourceDir) {
            $self->logError("Source \"$sSourceDir\" is not readable. Backup set skipped.");
            return undef;
        }
    }

    return $sSourceDir;
}

sub run_cmd {
    my $self= shift;
    my $cmd= shift;

    my ($sStdOut, $sStdErr, $iExit, $sError);

    my ($fhCmdOut, $sCmdOutFile)= $self->tempfile();
    close $fhCmdOut;
    my ($fhCmdErr, $sCmdErrFile)= $self->tempfile();
    close $fhCmdErr;

    system("$cmd > '$sCmdOutFile' 2> '$sCmdErrFile'");
    $iExit= $?;
    if ($iExit == -1) {
        $sError= "failed to execute: $!";
    }
    elsif ($iExit & 127) {
        $sError= sprintf "cmd died with signal %d, %s coredump",
            ($iExit & 127), ($iExit & 128) ? "with" : "without";
    }

    if (-s $sCmdErrFile && open ($fhCmdErr, $sCmdErrFile)) {
        $sStdErr= join '', (<$fhCmdErr>);
        close $fhCmdErr;
    }
    if (-s $sCmdOutFile && open ($fhCmdOut, $sCmdOutFile)) {
        $sStdOut= join '', (<$fhCmdOut>);
        close $fhCmdOut;
    }
    return ($sStdOut, $sStdErr, $iExit, $sError);
}

1;
