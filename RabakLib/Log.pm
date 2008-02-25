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

use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK );

use Exporter;

@ISA = qw( Exporter );
@EXPORT = qw( logger LOG_DEBUG_LEVEL LOG_DEFAULT_LEVEL LOG_INFO_LEVEL LOG_WARN_LEVEL LOG_ERROR_LEVEL );

our $oLog;

# my ( $LOGLEVEL, $CONFESS )      = ( 0, 0 );

# my $LOGGER              = {
#     Default => [ \&std_logger ]
# };

BEGIN {
    $oLog = {
        PREFIX => '',
        CATEGORY => '',
        MESSAGES => '',
        LOG_FH => undef,
        FILE_NAME => '',
        REAL_FILE_NAME => '',   # real file name (tempfile for remote log files)
        IS_NEW => 0,
        STDOUT_PREFIX => '',    # prefix for stdout prints (may be "# " for comments)
        
        ERRORCOUNT => 0,
        WARNCOUNT => 0,

        TARGET => undef,

        SWITCH_PRETEND => 0,
        SWITCH_LOGGING => 0,
    };
    

    bless $oLog, "RabakLib::Log";
}

sub new {
    my $class = shift;
    return $oLog;
}

sub logger {
    return RabakLib::Log->new();
}

sub init {
    my $class= shift;
    my $hConf= shift;

    $oLog->{SWITCH_PRETEND}= $hConf->get_switch('pretend');
    $oLog->{SWITCH_LOGGING}= $hConf->get_switch('logging');

    # $hConf->set_log($self);
    # bless $self, $class;
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub LOG_DEBUG_LEVEL   { 5 }
sub LOG_DEFAULT_LEVEL { 4 }
sub LOG_INFO_LEVEL    { 3 }
sub LOG_WARN_LEVEL    { 2 }
sub LOG_ERROR_LEVEL   { 1 }


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
    my $bIsNew= !$oTarget->isFile($sFileName);

    if ($oTarget->is_remote()) {
        ($self->{LOG_FH}, $self->{REAL_FILE_NAME})= $oTarget->local_tempfile;
    }
    else {
        unless (CORE::open ($self->{LOG_FH}, ">>$sFileName")) {
            $self->{LOG_FH}= undef;
            return $!;
        }
    }
    if (!$bIsNew) {
        my $fh= $self->{LOG_FH}; 
        print $fh "\n", "=" x 80, "\n\n";
    }
    return '';
}

sub close {
    my $self= shift;

    return unless $self->{TARGET};
    CORE::close $self->{LOG_FH} if $self->{LOG_FH};
    $self->{LOG_FH}= undef;
    if ($self->{TARGET}->is_remote()) {
        logger->error($self->{TARGET}->get_error()) unless ($self->{TARGET}->copyLocalFileToRemote($self->{REAL_FILE_NAME}, $self->{FILE_NAME}, 1));
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

sub set_stdout_prefix {
    my $self= shift;
    my $sPrefix= shift || '';
    
    $self->{STDOUT_PREFIX}= $sPrefix;
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

sub debug {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_DEBUG_LEVEL, @sMessage ] if wantarray;
    $self->log($self->debug(@_));
}

sub info {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_INFO_LEVEL, @sMessage ] if wantarray;
    $self->log($self->info(@_));
}

sub warn {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_WARN_LEVEL, @sMessage ] if wantarray;
    $self->log($self->warn(@_));
}

sub error {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_ERROR_LEVEL, @sMessage ] if wantarray;
    $self->log($self->error(@_));
}

sub exitError {
    my $self= shift;
    my $iExit=shift || 0;
    my @sMessage= @_;

    $self->error(@sMessage);
    exit $iExit if $iExit;
}

sub log {
    my $self= shift;
    my @sMessage= @_;

    for my $sMessage (@sMessage) {
        if (ref $sMessage eq "ARRAY") {
            $self->_levelLog(@{ $sMessage });
            next;
        }
        $self->_levelLog(LOG_DEFAULT_LEVEL, $sMessage);
    }
}

sub _levelLog {
    my $self= shift;
    my $iLevel= shift;
    my @sMessage= @_;

    my $sMsgPref;
    if ($iLevel == LOG_ERROR_LEVEL) {
        $sMsgPref= "ERROR:   ";
        $self->{ERRORCOUNT}++
    }
    elsif ($iLevel == LOG_WARN_LEVEL) {
        $sMsgPref= "WARNING: ";
        $self->{WARNCOUNT}++
    }
    elsif ($iLevel == LOG_INFO_LEVEL) {
        $sMsgPref= "INFO:    ";
    }
    elsif ($iLevel == LOG_DEBUG_LEVEL) {
        $sMsgPref= "DEBUG:   ";
    }
    else {
        $sMsgPref= "LOG($iLevel):  ";
    }

    for my $sMessage (@sMessage) {
        next unless $sMessage;
        if (ref $sMessage eq "ARRAY") { # call recursive for nested arrays
            my $iMyLevel = shift @{ $sMessage };
            $iMyLevel= $iLevel if $iMyLevel > $iLevel; # use highest log level TODO: does that make sense?
            $self->_levelLog($iMyLevel, @{ $sMessage });
            next;
        }
        chomp $sMessage;
        $sMessage= '[' . $self->{PREFIX} . "] $sMessage" if $self->{PREFIX};
        # print message to stdout
        print "$self->{STDOUT_PREFIX}$sMsgPref$sMessage\n" if $iLevel <= $self->{SWITCH_LOGGING};

        next unless $self->{SWITCH_LOGGING} && !$self->{SWITCH_PRETEND};

        $sMessage= $self->{CATEGORY} . "\t$sMessage" if $self->{CATEGORY};
        $sMessage= _timestr() . "\t$sMsgPref$sMessage\n";

        $self->{UNFLUSHED_MESSAGES} .= $sMessage;
        $self->{MESSAGES} .= $sMessage if $iLevel <= $self->{SWITCH_LOGGING};
    }
    $self->_flush();
}

1;
