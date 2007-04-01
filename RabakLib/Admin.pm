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
        SET => '',
        TERM => Term::ReadLine->new('RabakLib::Sdmin'),
    };
    bless $self, $class;
}

sub do_set_list {
    my $self= shift;

    $self->{CONF_FILE}->print_set_list();
}

sub do_set {
    my $self= shift;
    my $sSet= shift || '';

    my $oConf= $self->{CONF};
    if (defined $oConf->{VALUES}{$sSet}) {
        $self->{SET}= $oConf->{VALUES}{$sSet};
        return;
    }

    # Reset SET. If we do batch processing one day, we don't want to process on the wrong set.
    if ($sSet) {
        $self->{SET}= undef;
        print "Backup set \"$sSet\" doesn't exist.\n";
    }
    $self->do_set_list();
}

sub do_help {
    print "set         List available sets\n";
    print "set SET     Use backup set SET\n";
    print "conf [SET]  Show set config (Current if SET is omitted)\n";
    print "quit        Quit program\n";
}

sub _need_set {
    my $self= shift;

    unless ($self->{SET}) {
        print "Try 'set SET' first!\n";
        return undef;
    }
    return $self->{SET};
}

sub _check_set {
    my $self= shift;
    my $sSet= shift;

    return -1 unless $sSet;

    my $oSet= $self->{CONF}{VALUES}{$sSet};
    return $oSet if $oSet;

    print "No backup set '$sSet'. Try 'set' for a list of available backup sets!\n";
    return undef;
}

sub do_conf {
    my $self= shift;
    my $sSet= shift || '';

    my $oSet= $self->_check_set($sSet) or return;
    ref $oSet or $oSet= $self->_need_set() or return;
    $oSet->show();
}

sub loop() {
    my $self= shift;

    # eval ("\$self->{TERM}->read_history('~/.rabak_history')") or print $@;

    while (1) {
        my $sPrompt= $self->{CONF_FILE}->filename();
        $sPrompt .= ':' . $self->{SET}{NAME} if $self->{SET};
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
            if ($@ !~ /^Can\'t locate/) {
                print "Error: $@\n";
                next;
            }
        }
        print "Syntax error!\n";
        do_help();
    }

    # eval ("\$self->{TERM}->write_history('~/.rabak_history')");

    return 0;
}

1;

__END__

set
set bla

