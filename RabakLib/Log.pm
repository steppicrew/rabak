#!/usr/bin/perl

package RabakLib::Log;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::Conf;

# use File::Spec ();
# use POSIX qw(strftime);

sub new {
    my $class= shift;
    my $hConf= shift;
    my $self= {
        ERRORCODE => 0,
        HAS_ERRORS => 0,
        CONF => $hConf,
    };
    bless $self, $class;
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub _timestr {
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

sub xerror {
    my $self= shift;
    my $sMsg= shift;
    my $iExit= shift || 0;

    if ($self->{CONF}->get_value('switch.logging')) {
        my $sName= $self->{CONF}->get_value('name') || '';
        $sMsg= _timestr() . "\t$sName\t$sMsg";
        $sMsg .= "\n";
        print $sMsg;
    }
    exit $iExit if $iExit;

    # $self->{HAS_ERRORS}= 1;

    $self->{ERRORCODE}= 9;
}

sub start {
}

sub xlog {
    my $self= shift;
    my $sMessage= shift;
    my $iLevel= shift || 0;

    # our $fwLog;
    return if $self->{CONF}->get_value('switch.quiet');

    print "$sMessage\n";
    return unless $self->{LOGFILE} && $self->get_value('switch.logging') && !$self->get_value('switch.pretend');

    my $fwLog= $self->{LOGFILE};
    print $fwLog _timestr() . "\t$sMessage\n";
}

1;
