#!/usr/bin/perl -w

# See Licence.txt for licence

use strict;

use RabakLib::ConfFile;
use RabakLib::Set;

use Data::Dumper;
use Getopt::Std;

our $VERSION= "0.3.1";
our $DEBUG= 0;

$Getopt::Std::STANDARD_HELP_VERSION= 1;

our $hConfFile;
our $hConf;
# our $iErrorCode= 0;

our $opt_q;
# our $opt_v;
our $opt_l;
our $opt_p;
our $opt_c;
our $opt_h;
our $opt_i;

getopts("qplhc:i:") or die HELP_MESSAGE();

our $sCmd= shift @ARGV || '';

if ($opt_h) {
    help($sCmd);
    exit 1;
}

cmd_backup() if $sCmd eq 'backup';
cmd_conf()   if $sCmd eq 'conf';
cmd_rmfile() if $sCmd eq 'rmfile';
cmd_doc()    if $sCmd eq 'doc';

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
        _conf_read();
        print "Available backup sets:\n";
        my $bFound= 0;
        foreach (sort keys %{ $hConf }) {
            next unless ref $hConf->{$_} && defined $hConf->{$_}{title} && defined $hConf->{$_}{source} && defined $hConf->{$_}{target};
            print "  $_ - " . $hConf->{$_}{title} . ", backs up \"" . $hConf->{$_}{source} . "\" to \"" . $hConf->{$_}{target} . "\"\n";
            $bFound= 1;
        }
        print "None. Configuration expected in file \"" . $hConfFile->filename() . "\"\n" unless $bFound;
        exit 0;
    }
    my $hBakSet= _cmd_setup($sBakSet, 1);
    $hBakSet->show($sBakSet);
    exit 0;
}

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
#  HELPER FUNCTIONS
# -----------------------------------------------------------------------------

sub _conf_read {
    $hConfFile= RabakLib::ConfFile->new($opt_c ? $opt_c : 'rabak.cf');
    $hConf= $hConfFile->conf();
    $hConf->set_defaults({
        'switch.pretend' => $opt_p,
        # 'switch.verbose' => $opt_v,
        'switch.quiet' => $opt_q,
        'switch.logging' => $opt_l,
	'switch.targetid' => $opt_i,
    });
}

sub _cmd_setup {
    my $sBakSet= shift;
    my $bSkipChecks= shift;

    _conf_read();
    my $hSet= RabakLib::Set->new($hConf, $sBakSet, $bSkipChecks);
    if ($hSet->{'.ERROR'}) {
        print $hSet->{'.ERROR'} . "\n";
        _exit(3);
    }
    return $hSet;
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
  -c <file> Use <file> for configuration
  -i <id>   Save in disk with targetgroup value <id>
  -l        Log to file
  -p        Pretend
  -q        Be quiet
  --version Show version
  --help    Show (this) help
";

#TODO: Implement:
#  -v        Be verbose

        return;
    }
    print $sHelp{$sCmd};
}

sub HELP_MESSAGE {
    help();
    return "Gave up";
}

1;