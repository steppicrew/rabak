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
use Rabak::Set;

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
    $self->{SET}= undef;
    $self->{TERM}= Term::ReadLine->new('Rabak::Cmd::Admin');
    $self->{RANGE_FROM}= undef;
    $self->{RANGE_UNTIL}= undef;

    bless $self, $class;
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak admin [options] [<backup set>]',
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

sub _needSet {
    my $self= shift;

    unless ($self->{SET}) {
        print "Try 'set SET' or 'mount SET' first!\n";
        return undef;
    }
    return $self->{SET};
}

sub _checkSet {
    my $self= shift;
    my $sSet= shift;

    return $self->_needSet() unless $sSet;

    my $oSet= $self->_getSet($sSet);
    # my $oSet= $self->{CONF}{VALUES}{$sSet};
    return $oSet if $oSet;

    print "Try 'set' for a list of available backup sets!\n";
    return undef;
}

sub _getSet {
    my $self= shift;
    my $sSet= shift;

    my $oSet= Rabak::Set->new($sSet, $self->{CONF});
    if ($oSet->{ERROR}) {
        print $oSet->{ERROR} . ".\n";
        return undef;
    }
    return $oSet;
}

sub _doSetList {
    my $self= shift;

    _noArg(shift) or return;

    $self->{CONF_FILE}->printSetList();
}

# DETECTED UNUSED: doSet
sub doSet {
    my $self= shift;
    my $sSet= shift || '';

    _noArg(shift) or return;

    my $oConf= $self->{CONF};
    if (defined $oConf->{VALUES}{$sSet}) {
        # $self->{SET}= $oConf->{VALUES}{$sSet};
        $self->{SET}= $self->_getSet($sSet);
        return;
    }

    # Reset SET. If we do batch processing one day, we don't want to process on the wrong set.
    if ($sSet) {
        $self->{SET}= undef;
        print "Backup set \"$sSet\" doesn't exist. Try 'set'!\n";
        return;
    }
    $self->_doSetList();
}

# DETECTED UNUSED: doHelp
sub doHelp {
    print "set         List available sets\n";
    print "set SET     Use backup set SET\n";
    print "mount [SET] Mount set (Current if SET is omitted)\n";
    print "conf [SET]  Show set config (Current if SET is omitted)\n";
    print "quit        Quit program\n";
    # bakdirs
}

# DETECTED UNUSED: doMount
sub doMount {
    my $self= shift;
    my $sSet= shift || '';

    _noArg(shift) or return;

    $self->{SET}= $self->_checkSet($sSet) or return;
    $self->{SET}->mount();
}

# DETECTED UNUSED: doUmount
sub doUmount() {
    _doUnmount(@_);
}

sub _doUnmount() {
    my $self= shift;

    my $oSet= $self->_needSet() or return;
    $self->{SET}->unmount();
}

# DETECTED UNUSED: doBakdirs
sub doBakdirs {
    my $self= shift;

    _noArg(shift) or return;

    my $oSet= $self->_needSet() or return;
    my @sDirs= $oSet->collect_bakdirs([ '.' . $oSet->getValue('name') ], [ '' ]);

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
    my $sSet= shift || '';

    _noArg(shift) or return;

    my $oSet= $self->_checkSet($sSet) or return;
    $oSet->show();
}

sub loop() {
    my $self= shift;

    print "Caution! Admin is experimental and mostly useless!\n";

    # eval ("\$self->{TERM}->read_history('~/.rabak_history')") or print $@;

    while (1) {
        my $sPrompt= $self->{CONF_FILE}->filename();
        if ($self->{SET}) {
            $sPrompt .= '/' . $self->{SET}->getValue('name');

            # my $iMounts= scalar @{ $self->{SET}->getMounts() };
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
