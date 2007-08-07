#!/usr/bin/perl

package RabakLib::Conf;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::Log;

our $iElemNo= 0;
#our $oLog= RabakLib::Log->new();

# TODO: consistent new parameter convention
sub new {
    my $class = shift;
    my $self= shift || {};

    $self->{SET} = shift;
    $self->{ERRORCODE}= undef;

    $self->{NAME}= "elem_" . ($iElemNo++);
    
    $self->{VALUES}= {} unless ref $self->{VALUES};
    bless $self, $class;
    $self->set_log($self->{SET}->get_log()) if $self->{SET};
    return $self;
}

sub get_raw_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sDefault= shift || undef;
    
    if ($sName =~ s/^\&//) {
        logger->warn("It seems you are trying to read a value instead of an object reference ('&$sName')!");
    }

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        return $sDefault unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
    return $sDefault unless defined $self->{VALUES}{$sName};
    return $sDefault if $self->{VALUES}{$sName} eq '*default*';
    return $self->{VALUES}{$sName} unless ref $self->{VALUES}{$sName};
    return $sDefault;
}

sub remove_backslashes_part1 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    if ($sValue =~ /\\$/) {
        logger->warn("Conf-File contains lines ending with backslashes!");
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
        logger->warn("Referencing objects without leading '&' is deprecated. Please specify '&$sName'");
    }
    return $self;
}

sub set_values {
    my $self= shift;
    my $hValues= shift;
    for my $sName (keys(%$hValues)) {
        $self->set_value($sName, $hValues->{$sName}) if defined $hValues->{$sName};
    }
}

sub set_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sValue= shift;

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        $self->{VALUES}{$_}= RabakLib::Conf->new() unless ref $self->{VALUES}{$_};
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
