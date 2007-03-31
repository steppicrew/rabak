#!/usr/bin/perl

package RabakLib::Admin;

use warnings;
use strict;

use Data::Dumper;

use RabakLib::ConfFile;
use RabakLib::Set;

sub new {
    my $class = shift;
    my $hConf= shift || {};
    my $self= {
        CONF => $hConf,
        SET => '',
    };
    bless $self, $class;
}

sub do_set_list {
    my $self= shift;

    print "Available backup sets:\n";
    my $bFound= 0;
    my $oConf= $self->{CONF};
    foreach (sort keys %{ $oConf }) {
        next unless ref $oConf->{$_} && defined $oConf->{$_}{title} && defined $oConf->{$_}{source} && defined $oConf->{$_}{target};
        print "  $_ - " . $oConf->{$_}{title} . ", backs up \"" . $oConf->{$_}{source} . "\" to \"" . $oConf->{$_}{target} . "\"\n";
        $bFound= 1;
    }
    print "None." unless $bFound;
}

sub do_set {
    my $self= shift;
    my $sSet= shift || '';

    my $oConf= $self->{CONF};
    if (defined $oConf->{$sSet}) {
        $self->{SET}= $sSet;
        return;
    }

    print "Backup set \"$sSet\" doesn't exist.\n" if $sSet;
    $self->do_set_list();
}

sub do_help {
    print "set       List available sets\n";
    print "set SET   Use backup set SET\n";
    print "quit      Quit program\n";
}

sub loop() {
    my $self= shift;

    while (1) {
        print $self->{SET};
        print '> ';
        my $line= <STDIN>;

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

        my $sCmd= shift @aArgs || '';
        if ($sCmd eq 'set') {
            $self->do_set(@aArgs);
        }
        elsif ($sCmd eq 'help') {
            $self->do_help(@aArgs);
        }
        elsif ($sCmd eq 'quit' || $sCmd eq 'exit') {
            last;
        }
        elsif ($sCmd ne '') {
            print "Syntax error!\n";
            do_help();
        }

        # print join("::", @aArgs);
        # $line =~ s/\"([^\"]*)\"/\"\"/g;
        # print Dumper($self->{CONF});
        # print "\n";
    }

    return 0;
}

1;

__END__

set
set bla

