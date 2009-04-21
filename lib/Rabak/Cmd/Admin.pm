#!/usr/bin/perl

# Badly broken! Must get a complete renovation or be thrown away.

package Rabak::Cmd::Admin;

use warnings;
use strict;

BEGIN {
    # Have to do this because Term::ReadLine signals warnings.
    # FIXME: Is there a better solution?

    local $SIG{'__WARN__'} = sub {};
    eval 'use Term::ReadLine; 1';
}

use Data::Dumper;

use Rabak::ConfFile;
use Rabak::Job;

use vars qw(@ISA);

@ISA= qw( Rabak::Cmd );

################################################################################
#       Public
################################################################################

sub new {
    my $class = shift;
    my $oConfFile= shift || {};

    my $self= $class->SUPER::new();
    $self->{CONF_FILE}= undef;
    $self->{CONF}= undef;
    $self->{JOB}= undef;
    $self->{TERM}= Term::ReadLine->new('Rabak::Cmd::Admin');
    $self->{RANGE_FROM}= undef;
    $self->{RANGE_UNTIL}= undef;

    bless $self, $class;
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak admin [options] [<job name>]',
        'one liner',
        'description',
    );
}

sub run {
    my $self= shift;

    $self->warnOptions([ ]);

    $self->{CONF_FILE}= $self->readConfFile();
    $self->{CONF}= $self->{CONF_FILE}->conf();

    $self->loop();
}

################################################################################
#       Private
################################################################################

sub _noArg {
    return 1 unless defined shift;
    print "Invalid arguments. Try 'help'!\n";
    return 0;
}

sub _needJob {
    my $self= shift;

    unless ($self->{JOB}) {
        print "Try 'job JOB' or 'mount JOB' first!\n";
        return undef;
    }
    return $self->{JOB};
}

sub _checkJob {
    my $self= shift;
    my $sJob= shift;

    return $self->_needJob() unless $sJob;

    my $oJob= $self->_getJob($sJob);
    # my $oJob= $self->{CONF}{VALUES}{$sJob};
    return $oJob if $oJob;

    print "Try 'job' for a list of available job names!\n";
    return undef;
}

sub _getJob {
    my $self= shift;
    my $sJob= shift;

    my $oJob= Rabak::Job->new($sJob, $self->{CONF});
    if ($oJob->{ERROR}) {
        print $oJob->{ERROR} . ".\n";
        return undef;
    }
    return $oJob;
}

sub _doJobList {
    my $self= shift;

    _noArg(shift) or return;

    $self->{CONF_FILE}->printJobList();
}

# DETECTED UNUSED: doJob
sub doJob {
    my $self= shift;
    my $sJob= shift || '';

    _noArg(shift) or return;

    my $oConf= $self->{CONF};
    if (defined $oConf->{VALUES}{$sJob}) {
        # $self->{JOB}= $oConf->{VALUES}{$sJob};
        $self->{JOB}= $self->_getJob($sJob);
        return;
    }

    # Reset JOB. If we do batch processing one day, we don't want to process on the wrong set.
    if ($sJob) {
        $self->{JOB}= undef;
        print "Job \"$sJob\" doesn't exist. Try 'job'!\n";
        return;
    }
    $self->_doJobList();
}

# DETECTED UNUSED: doHelp
sub doHelp {
    print "job         List available jobs\n";
    print "job JOB     Use job JOB\n";
    print "mount [JOB] Mount JOB (Current if JOB is omitted)\n";
    print "conf [JOB]  Show JOB's config (Current if JOB is omitted)\n";
    print "quit        Quit program\n";
    # bakdirs
}

# DETECTED UNUSED: doMount
sub doMount {
    my $self= shift;
    my $sJob= shift || '';

    _noArg(shift) or return;

    $self->{JOB}= $self->_checkJob($sJob) or return;
    $self->{JOB}->mount();
}

# DETECTED UNUSED: doUmount
sub doUmount() {
    _doUnmount(@_);
}

sub _doUnmount() {
    my $self= shift;

    my $oJob= $self->_needJob() or return;
    $self->{JOB}->unmount();
}

# DETECTED UNUSED: doBakdirs
sub doBakdirs {
    my $self= shift;

    _noArg(shift) or return;

    my $oJob= $self->_needJob() or return;
    my @sDirs= $oJob->collect_bakdirs([ '.' . $oJob->getValue('name') ], [ '' ]);

    map { print "$_\n"; } @sDirs;
}

# DETECTED UNUSED: doRange
sub doRange {
    my $self= shift;
    my $sEq= shift || '';
    my $sValue= '';

    if ($sEq =~ /^(<=|>=|==)$/) {
        $sValue= shift || '';
        $self->{RANGE_FROM}= $sValue if $sEq =~ /^(>=|==)$/;
        $self->{RANGE_UNTIL}= $sValue if $sEq =~ /^(<=|==)$/;
    }
    elsif ($sEq) {
        $sValue= $sEq;
        $sEq= '==';
        $self->{RANGE_FROM}= $self->{RANGE_UNTIL}= $sValue;
    }
    else {
        # display range ..
    }

    _noArg(shift) or return;

    if (!$self->{RANGE_FROM} && !$self->{RANGE_UNTIL}) {
        print "No range.\n";
        return;
    }
    print "Range ";
    print $self->{RANGE_FROM} . " " if $self->{RANGE_FROM};
    print "..";
    print " " . $self->{RANGE_UNTIL} if $self->{RANGE_UNTIL};
    print ".\n";
}

# DETECTED UNUSED: doConf
sub doConf {
    my $self= shift;
    my $sJob= shift || '';

    _noArg(shift) or return;

    my $oJob= $self->_checkJob($sJob) or return;
    $oJob->show();
}

sub loop() {
    my $self= shift;

    print "Caution! Admin is experimental and mostly useless!\n";

    # eval ("\$self->{TERM}->read_history('~/.rabak_history')") or print $@;

    while (1) {
        my $sPrompt= $self->{CONF_FILE}->filename();
        if ($self->{JOB}) {
            $sPrompt .= '/' . $self->{JOB}->getValue('name');

            # my $iMounts= scalar @{ $self->{JOB}->getMounts() };
            my $iMounts= 0;

            $sPrompt .= ':' . $iMounts if $iMounts;
        }
        $sPrompt .= '> ';
        my $line= $self->{TERM}->readline($sPrompt);

        my @aArgs= ();
        my $sArg= '';
        my $bInQuot= '';
        for (split (/(\s+|\\.|\")/, "$line ")) {
            if ($_ =~ /\s/ && !$bInQuot) {
                push(@aArgs, $sArg), $sArg= '' if $sArg;
                next;
            }
            if ($_ eq '"') {
                push(@aArgs, $sArg), $sArg= '' if $sArg;
                $bInQuot= !$bInQuot;
                next;
            }
            $sArg .= $_;
        }
        do { print "Unmatched \".\n"; next; } if $bInQuot;

        my $sCmd= shift @aArgs or next;

        if ($sCmd eq 'quit' || $sCmd eq 'exit') {
            last;
        }
        elsif ($sCmd !~ /[^a-z]/) {
            eval("\$self->do_$sCmd(\@aArgs)");
            next unless $@;
            if ($@ !~ /^Can\'t locate.*Rabak::Admin/) {
                print "Error: $@\n";
                next;
            }
        }
        print "Syntax error. Try 'help'!\n";
    }

    # eval ("\$self->{TERM}->write_history('~/.rabak_history')");

    return 0;
}

1;
