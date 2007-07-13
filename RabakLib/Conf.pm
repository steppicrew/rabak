#!/usr/bin/perl

package RabakLib::Conf;

use warnings;
use strict;

# our @ISA = qw(Exporter);
# our @EXPORT = qw($sFile);

use Data::Dumper;

=pod

=head1 NAME

RabakLib::Conf - Handle Conf Files

=head1 SYNOPSYS

Format very similar to postfix config files:

    key1 = value1
    key2 = multi
        lined           # indent the following lines
    key3.prop1 = $key1  # -> key3.prop1 = value1
    key3.prop2 = $key1
        $key2           # -> key3.prop2 = value1 \n multi \n lined
    key4.prop3= $key3   # -> key4.prop3.prop1 = value1
                        #    key4.prop3.prop2 = value1 \n multi \n lined
=cut

sub new {
    my $class = shift;
    my $sName= shift || '';
    my $self= shift || {};
    $self->{DEFAULTS}= {};
    $self->{NAME}= $sName;
    $self->{VALUES}= {} unless ref $self->{VALUES};
    bless $self, $class;
}

# TODO: Default values!!

sub set_defaults {
    my $self= shift;
    my $hDefaults= shift;
    $self->{DEFAULTS}= $hDefaults;
}

sub get_raw_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift || undef;

    if ($sName=~ s/^\&//) {
        print "WARNING: It seems you try to read a value instead of a reference!";
    }

    return $self->{DEFAULTS}{$sName} if defined $self->{DEFAULTS}{$sName};

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        return $sDefault unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
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

    # make every "°" preceeded by "." (not space to keep word separators)
    $sValue =~ s/\°/\.\°/g;
    # replace every double backslash with "\_"
    $sValue =~ s/\\\\/\\\°/g;
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
    $sValue =~ s/\\\°/\\/g;
    $sValue =~ s/\.\°/\°/g;
    return $sValue;
}
sub remove_backslashes {
    my $self= shift;
    my $sValue= shift;

    return $self->remove_backslashes_part2($self->remove_backslashes_part1($sValue));
}

sub get_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift || undef;

    return $self->remove_backslashes($self->get_raw_value($sName, $sDefault));
}

sub get_node {
    my $self= shift;
    my $sName= shift || '';

    my $bDepricated= !($sName=~ s/^\&//);
    
    return undef if $sName eq '.';

    my @sName= split(/\./, $sName);
    for (@sName) {
        return undef unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
    if ($bDepricated && defined $self) {
        print "WARNING: Referencing objects without leading '&' is depricated\nPlease specify '&$sName'\n";
    }
    return $self;
}

sub set_value {
    my $self= shift;
    my $sName= shift;
    my $sValue= shift;

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        $self->{VALUES}{$_}= RabakLib::Conf->new($_) unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }

    # TODO: only allow assignment of undef to refs?
    $self->{VALUES}{$sName}= $sValue;
}

sub show {
    my $self= shift;
    my $sKey= shift || $self->{NAME};

    for (sort keys %{ $self->{VALUES} }) {
        next if $_ =~ /^\./;
        if (ref($self->{VALUES}{$_})) {
            # print Dumper($self->{VALUES}{$_}); die;
            $self->{VALUES}{$_}->show("$sKey.$_");
            next;
        }
        my $sValue= $self->get_value($_);
        $sValue =~ s/\n/\n\t/g;
        print "$sKey.$_ = $sValue\n";
    }
}

1;
