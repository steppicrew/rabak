#!/usr/bin/perl

package RabakLib::Log;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::Conf;

# use File::Spec ();
use POSIX qw(strftime);

sub new {
    my $class= shift;
    my $hConf= shift;
    my $self= {
        CONF => $hConf,

        PREFIX => '',
        CATEGORY => '',
        MESSAGES => '',
        LOG_FH => undef,
        FILE_NAME => '',
        IS_NEW => 0,

        DEFAULTLEVEL => 1,
        INFOLEVEL => 0,
        WARNLEVEL => -1,
        ERRLEVEL => -2,
    };
    bless $self, $class;
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub _timestr {
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

# sub start {
#     my $self= shift;
# }

sub _flush {
    my $self= shift;


    return unless $self->{LOG_FH} && $self->{UNFLUSHED_MESSAGES};
    my $fh= $self->{LOG_FH};
    print $fh $self->{UNFLUSHED_MESSAGES};

    $self->{UNFLUSHED_MESSAGES}= '';
}

sub clear {
    my $self= shift;

    $self->{UNFLUSHED_MESSAGES}= '';
    $self->{MESSAGES}= '';
}

sub get_messages {
    my $self= shift;

    return $self->{MESSAGES};
}

sub open {
    my $self= shift;
    my $sFileName= shift;

    $self->{FILE_NAME}= $sFileName;
    $self->{IS_NEW}= !-f $sFileName;

    unless (open ($self->{LOG_FH}, ">>$sFileName")) {
        $self->{LOG_FH}= undef;
        return $!;
    }
    return '';
}

sub close {
    my $self= shift;

    return unless $self->{LOG_FH};
    close $self->{LOG_FH};
    $self->{LOG_FH}= undef;
}

sub get_filename() {
    my $self= shift;

    return $self->{LOG_FH} ? $self->{FILE_NAME} : undef;
}

sub is_new {
    my $self= shift;
    return $self->{IS_NEW};
}

sub set_prefix {
    my $self= shift;
    my $sPrefix= shift || '';

    $self->{PREFIX}= $sPrefix;
}

sub set_category {
    my $self= shift;
    my $sPrefix= shift || '';

    $self->{CATEGORY}= $sPrefix;
}

sub log {
    my $self= shift;
    my @sMessage= @_;

    foreach my $sMessage (@sMessage) {
        if (ref $sMessage eq "ARRAY") {
            my @sLogMessage= @{ $sMessage };
            my $iLevel= shift @sLogMessage;
            $self->levelLog($iLevel, @sLogMessage);
            next;
        }
        $self->levelLog($self->{DEFAULTLEVEL}, $sMessage);
    }
}

sub levelLog {
    my $self= shift;
    my $iLevel= shift;
    my @sMessage= @_;

    foreach my $sMessage (@sMessage) {
        return if $self->{CONF}->get_value('switch.quiet');
    
        $sMessage= '[' . $self->{PREFIX} . "] $sMessage" if $self->{PREFIX};
        print "$sMessage\n" if $iLevel <= $self->{CONF}->get_value('switch.verbose');
    
        return unless $self->{CONF}->get_value('switch.logging') && !$self->{CONF}->get_value('switch.pretend') &&
            $iLevel <= $self->{CONF}->get_value('switch.verbose');
    
        $sMessage= $self->{CATEGORY} . "\t$sMessage" if $self->{CATEGORY};
        $sMessage= _timestr() . "\t$sMessage\n";
    
        $self->{UNFLUSHED_MESSAGES} .= $sMessage;
        $self->{MESSAGES} .= $sMessage;
    
    }
    $self->_flush();
}

1;
