#!/usr/bin/perl

package RabakLib::Admin;

use warnings;
use strict;

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
        print $self->{SET}{NAME} if $self->{SET};
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

