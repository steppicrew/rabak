#!/usr/bin/perl

package RabakLib::Cmd;

use Cwd;
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);

use RabakLib::ConfFile;
use RabakLib::Log;

use strict;
use warnings;

sub GetGlobalOptions {
    return {
        "conf" =>               [ "",  "s", "<file>",   "Use <file> for configuration" ],
        "i" =>                  [ "",  "s", "<value>",  "Save on device with targetgroup value <value> (Backward compatibility. Don't use!)" ],
        "log" =>                [ "",  "",  "",         "Log to file" ],
        "pretend" =>            [ "",  "",  "",         "Pretend (don't do anything, just tell what would happen)" ],
        "quiet" =>              [ "",  "",  "",         "Be quiet" ],
        "verbose" =>            [ "v", "",  "",         "Be verbose" ],
        "version" =>            [ "V", "",  "",         "Show version" ],
        "help" =>               [ "",  "",  "",         "Show (this) help" ],
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
            $sKey .= '=' . $hDefs->[1] if $hDefs->[1];
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
        die $@ if $@ !~ /^can\'t locate rabaklib\/cmd\/$sCmd\.pm/i;
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
    my $self= { OPTS => {}, ARGS => [], ERROR => undef, COMMAND_LINE => undef };
    bless $self, $class;
}

sub setup {
    my $self= shift;
    my $hOpts= shift;
    my $hArgs= shift;
    my $sCommandLine= shift;

    $self->{OPTS}= $hOpts;
    $self->{ARGS}= $hArgs;
    $self->{COMMAND_LINE}= $sCommandLine;
}

sub wantArgs {
    my $self= shift;
    my @aOk= @_;

    my %hOk= ();
    map { $hOk{$_}= 1 } @aOk;
    return 1 if $hOk{scalar @{$self->{ARGS}}};

    # overkill, but fun writing: :-)
    my @aNumbers= ("zero", "one", "two", "three", "four");
    my $sNs= $#aOk == 0 ? ($aOk[0] == 1 ? 'one argument' : $aNumbers[$aOk[0]] . " arguments") : 'or ' . $aNumbers[$aOk[-1]] . ' arguments';
    pop @aOk;
    my $sDelim= $#aOk ? ',' : '';
    map { $sNs = $aNumbers[$_] . "$sDelim $sNs"; $sDelim= ',' } reverse(@aOk);
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
        "/usr/local/rabak/rabak.cf",
        "./rabak.cf",
    );
    @sConfFiles= $self->{OPTS}{conf} if $self->{OPTS}{conf};
    my $oConfFile= RabakLib::ConfFile->new(@sConfFiles);
    my $oConf= $oConfFile->conf();

    # overwrite values with comand line switches
    my $sHostname= `hostname -f 2>/dev/null` || `hostname`;
    chomp $sHostname;
    $oConf->preset_values({
        '*.switch.pretend'      => $self->{OPTS}{pretend},
        '*.switch.verbose'      => $self->{OPTS}{verbose} ? LOG_VERBOSE_LEVEL : undef,
        '*.switch.logging'      => $self->{OPTS}{log},
        '*.switch.quiet'        => $self->{OPTS}{quiet},
        '*.switch.targetvalue'  => $self->{OPTS}{i},    # deprecate?
        '*.switch.version'      => 0, # $VERSION,
        '*.switch.hostname'     => $sHostname,
        '*.switch.commandline'  => $self->{COMMAND_LINE},
        '*.switch.configfile'   => $oConfFile->filename(),
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

    	print "# Backup Set '$sBakSet' is not properly defined:\n";
        print "# $sError\n";
        print "# The following values were found in the configuration:\n";
        $hSetConf->show();
    	return undef;
    }

    return $oSet;
}

sub getOptionsHelp {
    my $self= shift;
    my $hGlobalOptions= shift;
    my $hLocalOptions= shift;

    my $add= sub {
        my $sTitle= shift;
        my $hOptions= shift;
        my $sResult= '';
        foreach my $sKey (sort keys %$hOptions) {
            my $sDescr= join("\n" . (' ' x 23), split(/\n/, $hOptions->{$sKey}[3]));
            $sResult .= sprintf("    \-\-%-15s  %s\n", sprintf("%s %s", $sKey, $hOptions->{$sKey}[2]), $sDescr);
        }
        $sResult= "\n$sTitle:\n$sResult" if $sResult;
        return $sResult;
    };
    return $add->('Command options', $hLocalOptions) . $add->('General options', $hGlobalOptions);
}

sub warnOptions {
    my $self= shift;
    my $aUsed= shift || [];
    my %hUsed= ();

    map { $hUsed{$_}= 1 } @$aUsed;
    my %hOpts= %{ $self->{OPTS} };
    map { delete $hOpts{$_} } keys %hUsed;
    map { print "WARNING: Option '--$_' ignored!\n"; } keys %hOpts;
}

sub getOptions {
    return {};
}

sub help {
    return "Sorry, no help available.\n";
}

package RabakLib::Cmd::Error;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

sub new {
    my $class= shift;
    my $sError= shift;

    my $self= $class->SUPER::new();
    $self->{ERROR}= $sError;

    bless $self, $class;
}

sub run {
    print "Error: " . shift->{ERROR} . "\n";
}

1;
