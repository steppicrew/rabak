#!/usr/bin/perl

package RabakLib::CommonBase;

use warnings;
use strict;

# our @ISA = qw(Exporter);
# our @EXPORT = qw($sFile);

use Data::Dumper;

sub new {
    my $class = shift;
    my $self= shift || {};
    $self->{VALUES}= {} unless ref $self->{VALUES};
    bless $self, $class;
}

sub get_raw_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sDefault= shift || undef;

    if ($sName=~ s/^\&//) {
        print "WARNING: It seems you try to read a value instead of an object reference!";
    }

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        return $sDefault unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
    return $sDefault unless $self->{VALUES}{$sName};
    return $self->{VALUES}{$sName} unless ref $self->{VALUES}{$sName};
    return $sDefault;
}

sub remove_backslashes_part1 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    if ($sValue =~ /\\$/) {
        print "WARNING: Conf-File contains lines ending with backslashes!\n";
    }

    # make every "~" preceeded by "." (not space to keep word separators)
    $sValue =~ s/\~/\.\~/g;
    # replace every double backslash with "\~"
    $sValue =~ s/\\\\/\\\~/g;
    return $sValue;
}

sub remove_backslashes_part2 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    # Insert support for tab etc.. here
    # $sValue =~ s/\\t/\t/g;

    # remove all backslashes
    $sValue =~ s/\\(?!_)//g;
    # rereplace changes made in part1
    $sValue =~ s/\\\~/\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
}
sub remove_backslashes {
    my $self= shift;
    my $sValue= shift;

    return $self->remove_backslashes_part2($self->remove_backslashes_part1($sValue));
}

sub get_value {
    my $self= shift;
    return $self->remove_backslashes($self->get_raw_value(@_));
}

sub get_node {
    my $self= shift;
    my $sName= lc(shift || '');

    my $bDepricated= !($sName=~ s/^\&//);
    
    return undef if $sName eq '.';

    my @sName= split(/\./, $sName);
    for (@sName) {
        return undef unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
    if ($bDepricated && defined $self) {
        print "WARNING: Referencing objects without leading '&' is deprecated\nPlease specify '&$sName'\n";
    }
    return $self;
}

sub set_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sValue= shift;

    # TODO: only allow assignment of undef to refs?
    $self->{VALUES}{$sName}= $sValue;
}

1;
