#!/usr/bin/perl

package RabakLib::Log;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::Conf;
use RabakLib::PathBase;
use RabakLib::Path;

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
        REAL_FILE_NAME => '', # real file name (tempfile for remote log files)
        IS_NEW => 0,

        DEFAULTLEVEL => 2,
        INFOLEVEL => 1,
        WARNLEVEL => -1,
        ERRLEVEL => -2,
        
        ERRORCOUNT => 0,
        WARNCOUNT => 0,

        TARGET => undef,
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

    return unless $self->{TARGET} && $self->{UNFLUSHED_MESSAGES};

    my $fh= $self->{LOG_FH};
    print $fh $self->{UNFLUSHED_MESSAGES} if $self->{LOG_FH};

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
    my $oTarget= shift || RabakLib::Path->new();

    $self->close() if $self->{TARGET};

    $self->{TARGET}= $oTarget;

    $self->{FILE_NAME}= $self->{REAL_FILE_NAME}= $sFileName;
    $self->{IS_NEW}= !$oTarget->isFile($sFileName);

    if ($oTarget->remote) {
        ($self->{LOG_FH}, $self->{REAL_FILE_NAME})= $oTarget->local_tempfile;
    }
    else {
        unless (open ($self->{LOG_FH}, ">>$sFileName")) {
            $self->{LOG_FH}= undef;
            return $!;
        }
    }
    return '';
}

sub close {
    my $self= shift;

    return unless $self->{TARGET};
    close $self->{LOG_FH} if $self->{LOG_FH};
    $self->{LOG_FH}= undef;
    if ($self->{TARGET}->remote) {
        $self->log($self->errorMsg($self->{TARGET}->get_error)) unless ($self->{TARGET}->copyLoc2Rem($self->{REAL_FILE_NAME}, $self->{FILE_NAME}, 1));
    }
    $self->{TARGET}= undef;
}

sub get_filename() {
    my $self= shift;

    return $self->{TARGET} ? $self->{FILE_NAME} : undef;
}

sub get_errorCount {
    my $self= shift;
    return $self->{ERRORCOUNT};
}
sub get_warnCount {
    my $self= shift;
    return $self->{WARNCOUNT};
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

sub infoMsg {
    my $self= shift;
    my @sMessage= @_;

    return [ $self->{INFOLEVEL}, @sMessage ];
}

sub warnMsg {
    my $self= shift;
    my @sMessage= @_;

    return [ $self->{WARNLEVEL}, @sMessage ];
}

sub errorMsg {
    my $self= shift;
    my @sMessage= @_;

    return [ $self->{ERRLEVEL}, @sMessage ];
}

sub log {
    my $self= shift;
    my @sMessage= @_;

    for my $sMessage (@sMessage) {
        if (ref $sMessage eq "ARRAY") {
            $self->levelLog(@{ $sMessage });
            next;
        }
        $self->levelLog($self->{DEFAULTLEVEL}, $sMessage);
    }
}

sub levelLog {
    my $self= shift;
    my $iLevel= shift;
    my @sMessage= @_;

    return if $self->{CONF}->get_value('switch.quiet');

    my $sMsgPref;
    if ($iLevel == $self->{ERRLEVEL}) {
        $sMsgPref= "ERROR:   ";
        $self->{ERRORCOUNT}++
    }
    elsif ($iLevel == $self->{WARNLEVEL}) {
        $sMsgPref= "WARNING: ";
        $self->{WARNCOUNT}++
    }
    elsif ($iLevel == $self->{INFOLEVEL}) {
        $sMsgPref= "INFO:    ";
    }
    else {
        $sMsgPref= "LOG($iLevel):  ";
    }

    for my $sMessage (@sMessage) {
        next unless $sMessage;
        if (ref $sMessage eq "ARRAY") { # call recursive for nested arrays
            my $iMyLevel = shift @{ $sMessage };
            $iMyLevel= $iLevel if $iMyLevel > $iLevel; # use highest log level TODO: does that make sense?
            $self->levelLog($iMyLevel, @{ $sMessage });
            next;
        }
        chomp $sMessage;
        $sMessage= '[' . $self->{PREFIX} . "] $sMessage" if $self->{PREFIX};
        print "$sMsgPref$sMessage\n" if $iLevel <= $self->{CONF}->get_value('switch.verbose');

        next unless $self->{CONF}->get_value('switch.logging') &&
            !$self->{CONF}->get_value('switch.pretend');
#            $iLevel <= $self->{CONF}->get_value('switch.verbose');

        $sMessage= $self->{CATEGORY} . "\t$sMessage" if $self->{CATEGORY};
        $sMessage= _timestr() . "\t$sMsgPref$sMessage\n";

        $self->{UNFLUSHED_MESSAGES} .= $sMessage;
        $self->{MESSAGES} .= $sMessage if $iLevel <= $self->{CONF}->get_value('switch.verbose');

    }
    $self->_flush();
}

1;
