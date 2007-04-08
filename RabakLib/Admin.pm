#!/usr/bin/perl

package RabakLib::Admin;

use warnings;
use strict;

use Term::ReadLine;
use Data::Dumper;

use RabakLib::ConfFile;
use RabakLib::Set;

sub new {
    my $class = shift;
    my $oConfFile= shift || {};
    my $self= {
        CONF_FILE => $oConfFile,
        CONF => $oConfFile->conf(),
        SET => undef,
        TERM => Term::ReadLine->new('RabakLib::Admin'),
        RANGE_FROM => undef,
        RANGE_UNTIL => undef,
    };
    bless $self, $class;
}

sub _no_arg {
    return 1 unless defined shift;
    print "Invalid arguments. Try 'help'!\n";
    return 0;
}

sub _need_set {
    my $self= shift;

    unless ($self->{SET}) {
        print "Try 'set SET' or 'mount SET' first!\n";
        return undef;
    }
    return $self->{SET};
}

sub _check_set {
    my $self= shift;
    my $sSet= shift;

    return $self->_need_set() unless $sSet;

    my $oSet= $self->_get_set($sSet);
    # my $oSet= $self->{CONF}{VALUES}{$sSet};
    return $oSet if $oSet;

    print "Try 'set' for a list of available backup sets!\n";
    return undef;
}

sub _get_set {
    my $self= shift;
    my $sSet= shift;

    my $oSet= RabakLib::Set->new($self->{CONF}, $sSet, 1);
    if ($oSet->{ERROR}) {
        print $oSet->{ERROR} . ".\n";
        return undef;
    }
    return $oSet;
}

sub do_set_list {
    my $self= shift;

    _no_arg(shift) or return;

    $self->{CONF_FILE}->print_set_list();
}

sub do_set {
    my $self= shift;
    my $sSet= shift || '';

    _no_arg(shift) or return;

    my $oConf= $self->{CONF};
    if (defined $oConf->{VALUES}{$sSet}) {
        # $self->{SET}= $oConf->{VALUES}{$sSet};
        $self->{SET}= $self->_get_set($sSet);
        return;
    }

    # Reset SET. If we do batch processing one day, we don't want to process on the wrong set.
    if ($sSet) {
        $self->{SET}= undef;
        print "Backup set \"$sSet\" doesn't exist. Try 'set'!\n";
        return;
    }
    $self->do_set_list();
}

sub do_help {
    print "set         List available sets\n";
    print "set SET     Use backup set SET\n";
    print "mount [SET] Mount set (Current if SET is omitted)\n";
    print "conf [SET]  Show set config (Current if SET is omitted)\n";
    print "quit        Quit program\n";
    # bakdirs
}

sub do_mount {
    my $self= shift;
    my $sSet= shift || '';

    _no_arg(shift) or return;

    $self->{SET}= $self->_check_set($sSet) or return;
    $self->{SET}->mount();
}

sub do_umount() {
    do_unmount(@_);
}

sub do_unmount() {
    my $self= shift;

    my $oSet= $self->_need_set() or return;
    $self->{SET}->unmount();
}

sub do_bakdirs {
    my $self= shift;

    _no_arg(shift) or return;

    my $oSet= $self->_need_set() or return;
    my @sDirs= $oSet->collect_bakdirs();

    map { print "$_\n"; } @sDirs;
}

sub do_range {
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

    _no_arg(shift) or return;

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

sub do_conf {
    my $self= shift;
    my $sSet= shift || '';

    _no_arg(shift) or return;

    my $oSet= $self->_check_set($sSet) or return;
    $oSet->show();
}

sub loop() {
    my $self= shift;

    print "Caution! Admin is experimental and mostly useless!\n";

    # eval ("\$self->{TERM}->read_history('~/.rabak_history')") or print $@;

    while (1) {
        my $sPrompt= $self->{CONF_FILE}->filename();
        if ($self->{SET}) {
            $sPrompt .= '/' . $self->{SET}{NAME};
            my $iMounts= scalar @{ $self->{SET}->get_mounts() };
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
            if ($@ !~ /^Can\'t locate.*RabakLib::Admin/) {
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

__END__

set
set bla

