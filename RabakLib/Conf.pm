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
    my $self= shift || {};
    $self->{'.DEFAULTS'}= {};
    bless $self, $class;
}

# TODO: Default values!!

sub set_defaults {
    my $self= shift;
    my $hDefaults= shift;
    $self->{'.DEFAULTS'}= $hDefaults;
}

sub get_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift || undef;

    return $self->{'.DEFAULTS'}{$sName} if defined $self->{'.DEFAULTS'}{$sName};

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        return $sDefault unless ref $self->{$_};
        $self= $self->{$_};
    }
    return $self->{$sName} unless ref $self->{$sName};
    return $sDefault;
}

sub get_node {
    my $self= shift;
    my $sName= shift;

    my @sName= split(/\./, $sName);
    for (@sName) {
        return undef unless ref $self->{$_};
        $self= $self->{$_};
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
        $self->{$_}= RabakLib::Conf->new() unless ref $self->{$_};
        $self= $self->{$_};
    }
    # TODO: only allow assignment of undef to refs?
    $self->{$sName}= $sValue;
}

sub show {
    my $self= shift;
    my $sKey= shift;
    for (sort keys %{ $self }) {
        next if $_ =~ /^\./;
        if (ref($self->{$_})) {
  # print Dumper($self->{$_}); die;
            $self->{$_}->show("$sKey.$_");
            next;
        }
        my $sValue= $self->{$_};
        $sValue =~ s/\n/\n\t/g;
        print "$sKey.$_ = $sValue\n";
    }
}

1;