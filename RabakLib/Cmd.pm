#!/usr/bin/perl

package RabakLib::Cmd;

use Cwd;
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);

use RabakLib::ConfFile;
# use RabakLib::Set;
# use RabakLib::Admin;

use RabakLib::Log;

use strict;
use warnings;

sub Build {
    my $asArgs= shift;

    my @sqArgs= map {/\s/ ? "'$_'" : $_} $0, $asArgs;
    my $sCommandLine= join " ", @sqArgs;

    my %hOptDefs= (
        "conf" =>               [ "",  "s", "<file>",   "Use <file> for configuration" ],
        "i" =>                  [ "",  "s", "<value>",  "Save on device with targetgroup value <value> (Backward Compatibility. Don't use!)" ],
        "log" =>                [ "",  "",  "",         "Log to file" ],
        "pretend" =>            [ "",  "",  "",         "Pretend (don't do anything, just tell what would happen)" ],
        "quiet" =>              [ "",  "",  "",         "Be quiet" ],
        "verbose" =>            [ "",  "",  "",         "Be verbose" ],
        "version" =>            [ "",  "",  "",         "Show version" ],
        "help" =>               [ "",  "",  "",         "Show (this) help" ],
    );

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
    $calcOptArgs->(%hOptDefs);

# print Dumper($asArgs);
# print Dumper(\@sOptArgs);

    Getopt::Long::Configure("pass_through");
    GetOptionsFromArray($asArgs, $hOpts, @sOptArgs);
    if (scalar @$asArgs) {
        my $sCmd= lc shift @$asArgs;
        eval {
            local $SIG{'__WARN__'} = sub { chomp($sError= $_[0]); };
            require "RabakLib/Cmd/" . ucfirst($sCmd) . ".pm";
            my $sClass= "RabakLib::Cmd::" . ucfirst($sCmd);
            $oCmd= $sClass->new();
            1;
        };
        if ($@) {
            die $@ if $@ !~ /^Can\'t locate \S+\.pm/;
            $sError= "Unknown command: $sCmd";
        }
        else {
            $calcOptArgs->(%hOptDefs, %{ $oCmd->GetOptions() });
            eval {
                local $SIG{'__WARN__'} = sub { chomp($sError= $_[0]); };
                Getopt::Long::Configure("no_pass_through");
                GetOptionsFromArray($asArgs, $hOpts, @sOptArgs);
                1;
            };
            die $@ if $@;
        }
    }

    $oCmd= RabakLib::Cmd::Error->new($sError) if $sError;

    $oCmd->setup($hOpts, $asArgs, $sCommandLine);

# print Dumper($asArgs);
# print Dumper(\%hOpts);
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

sub want_args {
    my $self= shift;

    return unless scalar @{$self->{ARGS}} > 1;
    $self->{ERROR}= 'Zero or one Argument expected, got "' . join('", "', @{$self->{ARGS}}) . '"' . $/;
}

sub error {
    return shift->{ERROR};
}

sub readConf {
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

__END__



sub _conf_read {
    my @sConfFiles = (
        "$ENV{HOME}/.rabak/rabak.cf",
        "/etc/rabak/rabak.cf",
        "/etc/rabak.cf",
        "/usr/local/rabak/rabak.cf",
        "./rabak.cf",
    );
    @sConfFiles= ($sOpts{c}) if defined $sOpts{c};
    $oConfFile= RabakLib::ConfFile->new(@sConfFiles);
    $oConf= $oConfFile->conf();
    # overwrite values with comand line switches
    my $sHostname= `hostname -f 2>/dev/null` || `hostname`;
    chomp $sHostname;
    $oConf->preset_values({
        '*.switch.pretend' => $sOpts{p},
        '*.switch.verbose' => $sOpts{v} ? LOG_VERBOSE_LEVEL : undef,
        '*.switch.logging' => $sOpts{l},
        '*.switch.quiet' => $sOpts{q},
        '*.switch.targetvalue' => $sOpts{i},
        '*.switch.version' => $VERSION,
        '*.switch.hostname' => $sHostname,
        '*.switch.commandline' => $sCommandLine,
        '*.switch.configfile' => $oConfFile->filename(),
    });
    # print Dumper($oConf->get_node("switch")->{VALUES});
    return $oConfFile;
}

sub _cmd_setup {
    my $sBakSet= shift || '';

    _conf_read();
    my $hSetConf= $oConf->get_node($sBakSet);

    unless ($hSetConf) {
    	print "# Backup Set '$sBakSet' does not exist!\n";
    	_exit(3);
    }

    # Build a Set from Hash
    my $oSet= RabakLib::Set->newFromConf($hSetConf);
    my $sError= $oSet->get_validation_message();

    if ($sError) {
    	print "# Backup Set '$sBakSet' is not properly defined:\n";
        print "# $sError\n";
        print "# The following values were found in the configuration:\n";
        $hSetConf->show();
    	_exit(3);
    }

    return $oSet;
}


1;

__END__

sub run {
}

my $VERSION= "1.0_rc4";
my $DEBUG= 0;

$Getopt::Std::STANDARD_HELP_VERSION= 1;

my $oConfFile;
my $oConf;

my %sOpts= ();

my @sqArgs= map {/\s/ ? "'$_'" : $_} $0, @ARGV;
my $sCommandLine= join " ", @sqArgs;

getopts("hi:lc:pqv", \%sOpts) or die HELP_MESSAGE();

my $sCmd= shift @ARGV || '';

if ($sOpts{h}) {
    help($sCmd);
    exit 1;
}

cmd_backup() if $sCmd eq 'backup';
cmd_conf()   if $sCmd eq 'conf';
cmd_doc()    if $sCmd eq 'doc';

# Work in progress:
cmd_rmfile() if $sCmd eq 'rmfile';
cmd_admin()  if $sCmd eq 'admin';
cmd_dot()    if $sCmd eq 'dot';

usage(); # dies when done

# -----------------------------------------------------------------------------
#  COMMAND: BACKUP
# -----------------------------------------------------------------------------

sub cmd_backup {
    my $hBakSet= _cmd_setup(shift @ARGV);
    $hBakSet->backup();
    exit 0;
}

# -----------------------------------------------------------------------------
#  COMMAND: CONF
# -----------------------------------------------------------------------------

sub cmd_conf {
    my $sBakSet= shift @ARGV || '';
    if ($sBakSet eq '') {
        $oConfFile= _conf_read();
        $oConfFile->print_set_list();
        exit 0;
    }
    if ($sBakSet eq '*') {
        $oConfFile= _conf_read();
        $oConfFile->print_all();
        exit 0;
    }
    my $hBakSet= _cmd_setup($sBakSet, 1);
    $oConf->set_value("*.switch.warn_on_remote_access", 1);
    my @sConf= @{ $hBakSet->show() };
    pop @sConf;  # remove last []. (See RabalLib::Conf:show)
    print join "\n", @sConf, "";
    exit 0;
}

# -----------------------------------------------------------------------------
#  COMMAND: RMFILE
# -----------------------------------------------------------------------------

sub cmd_rmfile {
    my $hBakSet= _cmd_setup(shift @ARGV);
    _exit($hBakSet->rm_file(@ARGV));
}

# -----------------------------------------------------------------------------
#  COMMAND: DOC
# -----------------------------------------------------------------------------

sub cmd_doc {
    print `perldoc RabakLib::Doc`;
    _exit(0);
}

# -----------------------------------------------------------------------------
#  COMMAND: ADMIN
# -----------------------------------------------------------------------------

sub cmd_admin {
    # TODO: use command line switches
    my $oAdmin= RabakLib::Admin->new(_conf_read());
    # print Dumper($oAdmin); die;
    _exit($oAdmin->loop());
}

# -----------------------------------------------------------------------------
#  COMMAND: DOT
# -----------------------------------------------------------------------------

sub cmd_dot {
    my $sBakSet= shift @ARGV || '';
    unless ($sBakSet) {
    	print "# Please specify a Backup Set!\n";
        exit 0;
    }
    my $hBakSet= _cmd_setup(shift @ARGV);
    print $hBakSet->toDot();
    # print Dumper($hBakSet); die;
    _exit(0);
}

# -----------------------------------------------------------------------------
#  HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# sub eval_inside_rabakdir {
#     my $sCode= shift;
#
#     my $cwd= getcwd();
#     my $basedir= `dirname "$0"`;
#     chomp $basedir;
#     chdir $basedir if $basedir ne ''; # change
#
#     eval "$sCode 1;" or die @!;
#
#     chdir $cwd if $cwd ne '';
# }

sub _conf_read {
    my @sConfFiles = (
        "$ENV{HOME}/.rabak/rabak.cf",
        "/etc/rabak/rabak.cf",
        "/etc/rabak.cf",
        "/usr/local/rabak/rabak.cf",
        "./rabak.cf",
    );
    @sConfFiles= ($sOpts{c}) if defined $sOpts{c};
    $oConfFile= RabakLib::ConfFile->new(@sConfFiles);
    $oConf= $oConfFile->conf();
    # overwrite values with comand line switches
    my $sHostname= `hostname -f 2>/dev/null` || `hostname`;
    chomp $sHostname;
    $oConf->preset_values({
        '*.switch.pretend' => $sOpts{p},
        '*.switch.verbose' => $sOpts{v} ? LOG_VERBOSE_LEVEL : undef,
        '*.switch.logging' => $sOpts{l},
        '*.switch.quiet' => $sOpts{q},
        '*.switch.targetvalue' => $sOpts{i},
        '*.switch.version' => $VERSION,
        '*.switch.hostname' => $sHostname,
        '*.switch.commandline' => $sCommandLine,
        '*.switch.configfile' => $oConfFile->filename(),
    });
    # print Dumper($oConf->get_node("switch")->{VALUES});
    return $oConfFile;
}

sub _cmd_setup {
    my $sBakSet= shift || '';

    _conf_read();
    my $hSetConf= $oConf->get_node($sBakSet);

    unless ($hSetConf) {
    	print "# Backup Set '$sBakSet' does not exist!\n";
    	_exit(3);
    }

    # Build a Set from Hash
    my $oSet= RabakLib::Set->newFromConf($hSetConf);
    my $sError= $oSet->get_validation_message();

    if ($sError) {
    	print "# Backup Set '$sBakSet' is not properly defined:\n";
        print "# $sError\n";
        print "# The following values were found in the configuration:\n";
        $hSetConf->show();
    	_exit(3);
    }

    return $oSet;
}

# exitcodes:
# 1 usage, help
# 2 wrong parameter
# 3 error in conf file
# 9 other error
sub _exit {
    my $iErrorCode= shift || 0;
    usage() if $iErrorCode == 2;
    exit $iErrorCode;
}

sub usage {
    # print "usage: rabak [switches] <command>\n";
    HELP_MESSAGE();
    exit 1;
}

sub help {
    my $sCmd= shift || '';

    my %sHelp= (
        'backup' => "rabak [switches] backup <set>
Help not implemented.
",
        'conf'   => "rabak [switches] conf [<set>]
Help not implemented.
",
        'doc'   => "rabak doc
Help not implemented.
",

#         'rmfile' => "rabak [switches] rmfile <set> <file-or-dir-mask> [ <file-or-dir-mask> .. ]
# Help not implemented.
# ",

    );
    unless (defined $sHelp{$sCmd}) {
        print "Usage:\n";
        foreach (sort keys %sHelp) {
            print "  $1\n" if $sHelp{$_} =~ /^(.*)$/m;
        }
        print "
Possible switches:
  -c <file>  Use <file> for configuration
  -i <value> Save on device with targetgroup value <value>
  -l         Log to file
  -p         Pretend (don't do anything, just tell what would happen)
  -q         Be quiet
  -v         Be verbose
  --version  Show version
  --help     Show (this) help
";
        return;
#TODO:
#  implement verbosity levels
    }
    print $sHelp{$sCmd};
}

sub HELP_MESSAGE {
    help();
    return "Gave up";
}

sub VERSION_MESSAGE {
    print "This is rabak version $VERSION\n";
    return "Gave up";
}

1;
