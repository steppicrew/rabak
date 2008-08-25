#!/usr/bin/perl

package RabakLib::Log;

use warnings;
use strict;
no warnings 'redefine';

use Data::Dumper;
use RabakLib::Conf;
use RabakLib::Peer;
use RabakLib::Mountable;
use Mail::Send;

# use File::Spec ();
use POSIX qw(strftime);

use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK );

use Exporter;

@ISA = qw( Exporter );
@EXPORT = qw( logger LOG_DEBUG_LEVEL LOG_DEFAULT_LEVEL LOG_VERBOSE_LEVEL LOG_INFO_LEVEL LOG_WARN_LEVEL LOG_ERROR_LEVEL );

our $oLog;

# my ( $LOGLEVEL, $CONFESS )      = ( 0, 0 );

# my $LOGGER              = {
#     Default => [ \&std_logger ]
# };

BEGIN {
    $oLog = {
        PREFIX => '',
        CATEGORY => '',

        # vars for handling target logging
        LOG_MESSAGES => '',
        LOG_FH => undef,
        LOG_FILE_NAME => '',
        REAL_LOG_FILE_NAME => '',   # real file name (tempfile for remote log files)

        # vars for handling local logging (i.e. mail)
        MESSAGES => '',
        MSG_FH => undef,
        MSG_FILE_NAME => '',

        IS_NEW => 0,
        STDOUT_PREFIX => '',    # prefix for stdout prints (may be "# " for comments)
        
        ERRORCOUNT => 0,
        WARNCOUNT => 0,
        
        INDENT1 => 0,            # indenting for message grouping (before prefix)
        INDENT2 => 0,            # indenting for message grouping (after prefix)

        TARGET => undef,

        SWITCH_PRETEND => 0,
        SWITCH_LOGGING => 0,
        SWITCH_VERBOSITY => 3,
        SWITCH_QUIET => 0,
        
        FORCE_NL => 0,           # force new line on next print on screen
        LAST_PROGRESS_LENGTH => 0,# force new line on next print on screen
    };
    
    ($oLog->{MSG_FH}, $oLog->{MSG_FILE_NAME}) =
        RabakLib::Peer->local_tempfile();

    bless $oLog, __PACKAGE__;
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
    $oLog->{SWITCH_VERBOSITY}= $hConf->get_switch('verbose');
    $oLog->{SWITCH_VERBOSITY}= $oLog->LOG_DEFAULT_LEVEL unless defined $oLog->{SWITCH_VERBOSITY};
    $oLog->{SWITCH_QUIET}= $hConf->get_switch('quiet');

    $oLog->{SET_NAME}= $hConf->getName();
    $oLog->{EMAIL}= $hConf->get_value('email');
}

# -----------------------------------------------------------------------------
#  Messages
# -----------------------------------------------------------------------------

sub LOG_DEBUG_LEVEL   { 5 }
sub LOG_VERBOSE_LEVEL { 4 }
sub LOG_INFO_LEVEL    { 3 }
sub LOG_WARN_LEVEL    { 2 }
sub LOG_ERROR_LEVEL   { 1 }

sub LOG_DEFAULT_LEVEL { LOG_INFO_LEVEL() }

sub LOG_LEVEL_PREFIX  {
    return {
        LOG_ERROR_LEVEL()   => "ERROR",
        LOG_WARN_LEVEL()    => "WARNING",
        LOG_INFO_LEVEL()    => "INFO",
        LOG_VERBOSE_LEVEL() => "VERBOSE",
        LOG_DEBUG_LEVEL()   => "DEBUG",
    }
}

sub getLevelPrefix {
    my $self= shift;
    my $iLevel= shift;
    
    my $sResult= $self->LOG_LEVEL_PREFIX->{$iLevel} || "LOG($iLevel)";
    $sResult.= ":" . " "x(10 - length($sResult));
    return $sResult;
}

sub incIndent {
    my $self= shift;
    $self->{PREFIX} ? $self->{INDENT2}++ : $self->{INDENT1}++;
}

sub decIndent {
    my $self= shift;
    return $self->{INDENT2}-- if $self->{INDENT2};
    $self->{INDENT1}-- if $self->{INDENT1};
}

sub _timestr {
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

# sub start {
#     my $self= shift;
# }

sub _flush {
    my $self= shift;

    # flush messages to mail log file
    unless (defined $self->{MSG_FH}) {
        # reopen file if file was closed (get_message_file)
        if ($self->{MSG_FILE_NAME}) {
            $self->{MSG_FH}= undef unless CORE::open ($self->{MSG_FH}, ">>$self->{MSG_FILE_NAME}");
        }
    }
    my $fh= $self->{MSG_FH};
    if (defined $fh) {
        print $fh $self->{MESSAGES};
        $self->{MESSAGES}= '';
    }
    
    # flush messages to log file
    return unless $self->{TARGET} && $self->{LOG_MESSAGES};

    $fh= $self->{LOG_FH};
    if (defined $fh) {
        print $fh $self->{LOG_MESSAGES};
        $self->{LOG_MESSAGES}= '';
    }
}

sub clear {
    my $self= shift;

    $self->{LOG_MESSAGES}= '';
    $self->{MESSAGES}= '';
}

sub get_messages_file {
    my $self= shift;

    CORE::close($self->{MSG_FH}) if defined $self->{MSG_FH};
    return $self->{MSG_FILE_NAME};
}

sub open {
    my $self= shift;
    my $sFileName= shift;
    my $oTarget= shift || RabakLib::Peer::Mountable->new();

    $self->close() if $self->{TARGET};

    $self->{TARGET}= $oTarget;

    $self->{LOG_FILE_NAME}= $self->{REAL_LOG_FILE_NAME}= $sFileName;
    my $bIsNew= !$oTarget->isFile($sFileName);

    if ($oTarget->is_remote()) {
        ($self->{LOG_FH}, $self->{REAL_LOG_FILE_NAME})= $oTarget->local_tempfile;
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
        logger->error($self->{TARGET}->get_error()) unless ($self->{TARGET}->copyLocalFileToRemote($self->{REAL_LOG_FILE_NAME}, $self->{LOG_FILE_NAME}, 1));
    }
    $self->{TARGET}= undef;
}

sub _mail {
    my $self= shift;
    my ($sSubject, $fBody) = @_;
    
    my $sMailAddress= $self->{EMAIL}; 

    return 0 unless $sMailAddress;

    my $oMail = new Mail::Send Subject => $sSubject, To => $sMailAddress;
    # $msg->cc('user@host');
    my $fh = $oMail->open;
    my $sLine;
    my $fChompNL= sub {
        my $sLine= $fBody->();
        return undef unless defined $sLine;
        chomp $sLine;
        return "$sLine\n";
    };
    print $fh $sLine while defined ($sLine = $fChompNL->());
    $fh->close;

    return 1;
}

sub mailLog {
    my $self= shift;
    my $sSubject= shift;

    my $iErrors= $self->get_errorCount;
    my $iWarns= $self->get_warnCount;
    my $sErrWarn;
    $sErrWarn= "$iErrors error" if $iErrors; 
    $sErrWarn.= "s" if $iErrors > 1; 
    $sErrWarn.= ", " if $iErrors && $iWarns; 
    $sErrWarn.= "$iWarns warning" if $iWarns; 
    $sErrWarn.= "s" if $iWarns > 1; 
    $sSubject.= " ($sErrWarn)" if $sErrWarn;
    
    $sSubject= "RABAK '$self->{SET_NAME}': $sSubject";

    my $sFileName= $self->get_messages_file();
    my $fh;
    CORE::open $fh, "<$sFileName" or $fh= undef;
    my $fBody = sub {<$fh>};
    unless (defined $fh) {
        my @sBody= ("Error openening file '$sFileName'");
        $fBody = sub {shift @sBody};
    }

    my $result = $self->_mail($sSubject, $fBody);
    CORE::close $fh if defined $fh;
    return $result;
}

sub mailWarning {
    my $self= shift;
    my ($sSubject, @sBody) = @_;

    return $self->_mail("RABAK WARNING: $sSubject", sub {shift @sBody});
}

sub get_filename() {
    my $self= shift;

    return $self->{TARGET} ? $self->{LOG_FILE_NAME} : undef;
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
    $self->log($self->debug(@sMessage));
}

sub verbose {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_VERBOSE_LEVEL, @sMessage ] if wantarray;
    $self->log($self->verbose(@sMessage));
}

sub info {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_INFO_LEVEL, @sMessage ] if wantarray;
    $self->log($self->info(@sMessage));
}

sub warn {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_WARN_LEVEL, @sMessage ] if wantarray;
    $self->log($self->warn(@sMessage));
}

sub error {
    my $self= shift;
    my @sMessage= @_;

    return [ LOG_ERROR_LEVEL, @sMessage ] if wantarray;
    $self->log($self->error(@sMessage));
}

sub progress {
    my $self= shift;
    my $sMessage= shift;

    return if $self->{SWITCH_QUIET} || LOG_INFO_LEVEL > $self->{SWITCH_VERBOSITY};

    local $|= 1;
    my $iLength= length $sMessage;
    print "\r" . ' 'x$self->{LAST_PROGRESS_LENGTH} if $self->{LAST_PROGRESS_LENGTH} > $iLength;
    print "\r$sMessage";
    $self->{LAST_PROGRESS_LENGTH}= $iLength;
    $self->{FORCE_NL} = 1;
}

sub finish_progress {
    my $self= shift;
    my $sMessage= shift;

    $self->progress("$sMessage\n");
    $self->{FORCE_NL} = 0;
    $self->{LAST_PROGRESS_LENGTH}= 0;
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
    
    return unless join "", @sMessage;

    $self->{ERRORCOUNT}++ if $iLevel == LOG_ERROR_LEVEL;
    $self->{WARNCOUNT}++ if $iLevel == LOG_WARN_LEVEL;

    my $sMsgPref= $self->getLevelPrefix($iLevel);

    for my $sMessage (@sMessage) {
        next unless $sMessage;
        if (ref $sMessage eq "ARRAY") { # call recursive for nested arrays
            my $iMyLevel = shift @{ $sMessage };
            $iMyLevel= $iLevel if $iMyLevel > $iLevel; # use highest log level TODO: does that make sense?
            $self->incIndent();
            $self->_levelLog($iMyLevel, @{ $sMessage });
            $self->decIndent();
            next;
        }
        chomp $sMessage;
        $sMessage = "  " x $self->{INDENT2} . $sMessage;
        $sMessage = '[' . $self->{PREFIX} . "] $sMessage" if $self->{PREFIX};
        $sMessage = "  " x $self->{INDENT1} . $sMessage;
        unless ($self->{SWITCH_QUIET} || $iLevel > $self->{SWITCH_VERBOSITY}) {
            # print message to stdout
            print "\n" if $self->{FORCE_NL};
            $self->{FORCE_NL}= 0;
            print "$self->{STDOUT_PREFIX}$sMsgPref$sMessage\n";
        }

        next if $self->{SWITCH_PRETEND};

        $sMessage= $self->{CATEGORY} . "\t$sMessage" if $self->{CATEGORY};
        $sMessage= _timestr() . "\t$sMsgPref$sMessage\n";

        $self->{LOG_MESSAGES} .= $sMessage if $self->{SWITCH_LOGGING} && $iLevel <= LOG_VERBOSE_LEVEL;
        $self->{MESSAGES} .= $sMessage if $iLevel <= $self->{SWITCH_VERBOSITY};
    }
    $self->_flush();
}

1;
