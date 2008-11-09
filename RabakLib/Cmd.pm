#!/usr/bin/perl

package RabakLib::Cmd;

use Cwd;
use Data::Dumper;
use Getopt::Long 2.36 qw( GetOptionsFromArray );
use Term::ANSIColor;

use RabakLib::ConfFile;
use RabakLib::Log;
use RabakLib::Version;

use strict;
use warnings;

sub GetGlobalOptions {
    return {
        "conf" =>               [ "c", "=s", "<file>",  "Use <file> for configuration" ],
        "i" =>                  [ "",  "=s", "<value>", "Save on device with targetgroup value <value> (Depricated. Don't use!)" ],
        "pretend" =>            [ "p", "",  "",         "Pretend (don't do anything, just tell what would happen)" ],
        "quiet" =>              [ "q", "",  "",         "Be quiet" ],
        "verbose" =>            [ "v", "+",  "",        "Be verbose (May be specified more than once to be more verbose)" ],
        "color" =>              [ "",  "!",  "",        "Enable colored output" ],
        "help" =>               [ "h", "",  "",         "Show (this) help" ],
    };
}

sub Build {
    my $asArgs= shift;

    my @sqArgs= map {/\s/ ? "'$_'" : $_} $0, @$asArgs;
    my $sCommandLine= join " ", @sqArgs;
    my $oCmd;
    my $hOpts= {};
    my @sOptArgs;
    my $sError;

    my $calcOptArgs= sub {
        my %hOptDefs= @_;

        @sOptArgs= ();
        for my $sOpt (keys %hOptDefs) {
            my $hDefs= $hOptDefs{$sOpt};
            my $sKey= $sOpt;
            $sKey .= '|' . $hDefs->[0] if $hDefs->[0];
            $sKey .= $hDefs->[1] if $hDefs->[1];
            push @sOptArgs, $sKey;
        }
    };

    $calcOptArgs->(%{ GetGlobalOptions() });

    Getopt::Long::Configure("pass_through", "no_ignore_case");
    GetOptionsFromArray($asArgs, $hOpts, @sOptArgs);

    if ($hOpts->{help}) {
        unshift @$asArgs, 'help';
        delete $hOpts->{help};
    }

    $asArgs= [ 'help' ] unless scalar @$asArgs;

    my $sCmd= lc shift @$asArgs;
    eval {
        local $SIG{'__WARN__'} = sub { chomp($sError= $_[0]); };
        require "RabakLib/Cmd/" . ucfirst($sCmd) . ".pm";
        my $sClass= "RabakLib::Cmd::" . ucfirst($sCmd);
        $oCmd= $sClass->new();
        1;
    };
    if ($@) {
        my $sqCmd= quotemeta $sCmd;
        die $@ if $@ !~ /^can\'t locate rabaklib\/cmd\/$sqCmd\.pm/i;
        $sError= "Unknown command '$sCmd'. Please try 'rabak help' for further information.";
    }
    else {
        # $sError= "";    # Vorsicht: killt alle Warnings!
        $calcOptArgs->(%{ GetGlobalOptions() }, %{ $oCmd->getOptions() });
        eval {
            local $SIG{'__WARN__'} = sub { chomp($sError= $_[0]); };
            Getopt::Long::Configure("no_pass_through");
            GetOptionsFromArray($asArgs, $hOpts, @sOptArgs);
            delete $hOpts->{help};
            1;
        };
        die $@ if $@;
    }

    $oCmd= RabakLib::Cmd::Error->new($sError) if $sError;

    $oCmd->setup($hOpts, $asArgs, $sCommandLine);

    return $oCmd;
}

sub new {
    my $class= shift;
    my $self= {
        OPTS => {},
        ARGS => [],
        ERROR => undef,
        DATA => {
            COMMAND_LINE => undef,
            HOSTNAME => $class->hostname(),
            CONFIG_FILE => undef,
            USER => getpwuid($>),
        },
    };
    bless $self, $class;
}

sub hostname {
    my $sHostname= `hostname -f 2>/dev/null` || `hostname 2>/dev/null` || '(unknown)';
    chomp $sHostname;
    return $sHostname;
}

sub setup {
    my $self= shift;
    my $hOpts= shift;
    my $hArgs= shift;
    my $sCommandLine= shift;

    $self->{OPTS}= $hOpts;
    $self->{ARGS}= $hArgs;
    $self->{DATA}{COMMAND_LINE}= $sCommandLine;
    logger->setOpts({
        verbose   => $hOpts->{'verbose'} ? $hOpts->{'verbose'} + LOG_DEFAULT_LEVEL : undef,
        quiet     => $hOpts->{'quiet'},
        pretend   => $hOpts->{'pretend'},
        color     => defined $hOpts->{'color'} ? $hOpts->{'color'} : logger->IsColoredTerm() ,
    });
    
}

# generates error string regarding expected and gotten number of arguments
# if number does not match
sub wantArgs {
    my $self= shift;
    my @aOk= sort {$a <=> $b} @_;

    return 1 if scalar grep { $_ == scalar @{$self->{ARGS}} } @aOk;

    # overkill, but fun writing: :-)
    my $fNum= sub{("no", "one", "two", "three", "four")[$_[0]] || $_[0]};
    my $iLast= pop @aOk;
    my $sNs= $fNum->($iLast) . " argument" . ($iLast == 1 ? '' : 's');
    $sNs= join(", ", map {$fNum->($_)} @aOk) . ($#aOk ? ',' : '') . " or $sNs" if scalar @aOk;
    $self->{ERROR}= ucfirst($sNs) . ' expected, got "' . join('", "', @{$self->{ARGS}}) . '"' . $/;
    return 0;
}

sub error {
    return shift->{ERROR};
}

sub readConfFile {
    my $self= shift;

    my @sConfFiles = (
        "$ENV{HOME}/.rabak/rabak.cf",
        "/etc/rabak/rabak.cf",
        "/etc/rabak.cf",
        "./rabak.cf",
    );
    @sConfFiles= $self->{OPTS}{conf} if $self->{OPTS}{conf};
    my $oConfFile= RabakLib::ConfFile->new(@sConfFiles);
    my $oConf= $oConfFile->conf();
    $oConf->setCmdData($self->{DATA});

    $self->{DATA}{CONFIG_FILE}= $oConfFile->filename();

    # overwrite values with comand line switches
    $oConf->preset_values({
        '*.switch.pretend'      => $self->{OPTS}{pretend},
        '*.switch.targetvalue'  => $self->{OPTS}{i},    # deprecate?
    });
    # print Dumper($oConf->get_node("switch")->{VALUES});
    return $oConfFile;
}

sub getBakset {
    my $self= shift;
    my $sBakSet= shift || '';

    my $oConf= $self->readConfFile->conf();
    my $hSetConf= $oConf->get_node($sBakSet);

    unless ($hSetConf) {
    	$self->{ERROR}= "Backup Set '$sBakSet' does not exist!";
    	return;
    }

    # Build a Set from Hash
    my $oSet= RabakLib::Set->newFromConf($hSetConf);
    my $sError= $oSet->get_validation_message();

    if ($sError) {
    	$self->{ERROR}= "Backup Set '$sBakSet' is not properly defined!";

        logger->set_stdout_prefix("#");
    	logger->warn("Backup Set '$sBakSet' is not properly defined:",
            "$sError",
            "The following values were found in the configuration:",
        );
        logger->set_stdout_prefix();
        logger->print(@{ $hSetConf->show() });
    	return undef;
    }

    return ($oSet, $oConf) if wantarray;
    return $oSet;
}

sub getOptionsHelp {
    my $self= shift;
    my $hGlobalOptions= shift;
    my $hLocalOptions= shift;

    my $add= sub {
        my $sTitle= shift;
        my $hOptions= shift;
        my @sResult= ();
        foreach my $sKey (sort keys %$hOptions) {
            my @sDescr= split(/\n/, $hOptions->{$sKey}[3]);
            my $sLongOption= colored("--$sKey", 'bold');

            my $sLine= '    ';
            $sLine.= $hOptions->{$sKey}[0]
                ? (colored("-$hOptions->{$sKey}[0]", 'bold') . " | ")
                : "     ";
            $sLine.= colored("--$sKey", 'bold');
            $sLine.= " $hOptions->{$sKey}[2]";
            my $iLength= length(logger()->Uncolor($sLine));
            $sLine.= ' 'x(26 - $iLength) if $iLength < 26;
            $sLine.= shift @sDescr;
            push @sResult, $sLine, map { ' 'x26 . $_} @sDescr;
        }
        unshift @sResult, '', "$sTitle:", '' if scalar @sResult; 
        return @sResult;
    };
    return $add->('Command options', $hLocalOptions), $add->('General options', $hGlobalOptions);
}

# prints a warning for each given but unused general option
# gets array of used general options
sub warnOptions {
    my $self= shift;
    my $aUsed= shift || [];

    my %hOpts= %{ $self->{OPTS} };
    # delete keys for used general options and all command specific options
    map { delete $hOpts{$_} } (@$aUsed, 'color', keys %{ $self->getOptions() });
    # use scalar to make logger log (returns array otherwise)
    map { scalar logger->warn("Option '--$_' ignored!"); } keys %hOpts;
}

sub getOptions {
    return {};
}

sub Help {
    my $self= shift;
    my @sHelp= @_;
    @sHelp= ('Sorry, no help available!') unless scalar @sHelp;
    $sHelp[0]= colored($sHelp[0], 'bold');
    return @sHelp;
}

package RabakLib::Cmd::Error;

use vars qw(@ISA);
use RabakLib::Log;

@ISA= qw( RabakLib::Cmd );

sub new {
    my $class= shift;
    my $sError= shift;

    my $self= $class->SUPER::new();
    $self->{ERROR}= $sError;

    bless $self, $class;
}

sub run {
    logger->error("Error: " . shift->{ERROR});
}

1;
