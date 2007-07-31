#!/usr/bin/perl

package RabakLib::CommonBase;

use warnings;
use strict;

use Data::Dumper;

# TODO: consistent new parameter convention
sub new {
    my $class = shift;
    my $self= shift || {};
    $self->{SET} = shift;
    $self->{LOG_FILE}= undef;
    $self->{ERRORCODE}= undef;
    
    $self->{VALUES}= {} unless ref $self->{VALUES};
    bless $self, $class;
    $self->set_log($self->{SET}->get_log()) if $self->{SET};
    return $self;
}

sub set_log {
    my $self= shift;
    my $oLog= shift;
    $self->{LOG_FILE}= $oLog;

    if ($self->{VALUES}) {
        for my $oValue (values %{$self->{VALUES}}) {
            # if $oValue is an object and inherited from CommonBase set its log too
            if (ref($oValue)=~ /\:\:/ && $oValue->can("get_log")) {
                $oValue->set_log($oLog) if ! defined $oValue->get_log || $oValue->get_log != $oLog;
            }
        }
    }
    return $oLog;
}

sub get_log {
    my $self= shift;
    return $self->{LOG_FILE};
}

sub get_raw_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sDefault= shift || undef;
    
    if ($sName=~ s/^\&//) {
        $self->log($self->warnMsg("It seems you try to read a value instead of an object reference ('&$sName')!"));
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
        $self->log($self->warnMsg("Conf-File contains lines ending with backslashes!"));
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
        $self->log($self->warnMsg("Referencing objects without leading '&' is deprecated. Please specify '&$sName'"));
    }
    return $self;
}

sub infoMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->infoMsg(@sMessage) if $self->{LOG_FILE};
}

sub warnMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->warnMsg(@sMessage) if $self->{LOG_FILE};
}

sub errorMsg {
    my $self= shift;
    my @sMessage= @_;

    return $self->{LOG_FILE}->errorMsg(@sMessage) if $self->{LOG_FILE};
}

sub logExitError {
    my $self= shift;
    my $iExit=shift || 0;
    my @sMessage= @_;

    $self->logError(@sMessage);
    exit $iExit if $iExit;
}

sub logError {
    my $self= shift;
    my @sMessage= @_;

    $self->{LOG_FILE}->log($self->errorMsg(@sMessage)) if $self->{LOG_FILE};

    $self->{ERRORCODE}= 9;
}

sub log {
    my $self= shift;
    my @sMessage= @_;

    $self->{LOG_FILE}->log(@sMessage) if $self->{LOG_FILE};
}

sub set_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sValue= shift;

    # TODO: only allow assignment of undef to refs?
    $self->{VALUES}{$sName}= $sValue;
}

1;
