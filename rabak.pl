#!/usr/bin/perl

# See Licence.txt for licence

use warnings;
use strict;

# change to programs directory evalutaing use commands
my $basedir= `dirname "$0"`;
chomp $basedir;
`cd "$basedir"` if $basedir;

eval {
  use RabakLib::ConfFile;
  use RabakLib::Set;
  use RabakLib::Admin;
  1;
} or die @!;

use Data::Dumper;
use Getopt::Std;

our $VERSION= "0.4";
our $DEBUG= 0;

$Getopt::Std::STANDARD_HELP_VERSION= 1;

our $oConfFile;
our $oConf;
# our $iErrorCode= 0;

our $opt_q;
our $opt_v;
our $opt_l;
our $opt_p;
our $opt_c;
our $opt_h;
our $opt_i;

getopts("hi:lc:pqv") or die HELP_MESSAGE();

our $sCmd= shift @ARGV || '';

if ($opt_h) {
    help($sCmd);
    exit 1;
}

cmd_backup() if $sCmd eq 'backup';
cmd_conf()   if $sCmd eq 'conf';
cmd_rmfile() if $sCmd eq 'rmfile';
cmd_doc()    if $sCmd eq 'doc';
cmd_admin()  if $sCmd eq 'admin';

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
    my $hBakSet= _cmd_setup($sBakSet, 1);
    $hBakSet->show();
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
    die "Not implemented. Try \"perldoc RabakLib::Doc\"";
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
#  HELPER FUNCTIONS
# -----------------------------------------------------------------------------

sub _conf_read {
    $oConfFile= RabakLib::ConfFile->new($opt_c ? $opt_c : 'rabak.cf');
    $oConf= $oConfFile->conf();
    $oConf->set_defaults({
        'switch.pretend' => $opt_p,
        'switch.verbose' => defined $opt_v ? 4 : undef,
        'switch.quiet' => $opt_q,
        'switch.logging' => $opt_l,
        'switch.targetvalue' => $opt_i,
        'VERSION' => $VERSION,
    });
    return $oConfFile;
}

sub _cmd_setup {
    my $sBakSet= shift;
    my $bSkipChecks= shift;

    _conf_read();
    my $oSet= RabakLib::Set->new($oConf, $sBakSet, $bSkipChecks);
    if ($oSet->{ERROR}) {
        print $oSet->{ERROR} . "\n";
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
    my $iErrorCode= shift;
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
        'rmfile' => "rabak [switches] rmfile <set> <file-or-dir-mask> [ <file-or-dir-mask> .. ]
Help not implemented.
",
        'conf'   => "rabak [switches] conf [<set>]
Help not implemented.
",
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
  -p         Pretend
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

1;
