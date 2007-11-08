#!/usr/bin/perl

use strict;
use Getopt::Std;
use Data::Dumper;

use DupMerge::DupMerge;

$Getopt::Std::STANDARD_HELP_VERSION= 1;
my %opts= ();

getopts("hdpotvnc:zi:x:e:q", \%opts) or die HELP_MESSAGE();

my @sDirectories= @ARGV;
my $dm= DupMerge::DupMerge->new();

$dm->run(\@sDirectories, {
    digest_db_file  => $opts{c},
    temp_dir        => $opts{e},
    skip_zero       => $opts{z},
    quiet           => $opts{q},
    verbose         => $opts{v},
    ignore_devspans => $opts{d},
    min_size        => $opts{i},
    max_size        => $opts{x},
    ignore_perms    => $opts{p},
    ignore_owner    => $opts{o},
    ignore_time     => $opts{t},
    dryrun          => $opts{n},
    
    cb_infoS        => sub {print join "\n", @_; STDOUT->flush();}
});

sub HELP_MESSAGE {
    print "Usage:
$0 [<options> --] <path> [<path>]...
options: -h   Show this help message
         -d   Continue when directories span multiple devices (but ignore them)
              Program dies if paramter is not given and more than one device is used
         -p   Ignore permissions
         -o   Ignore ownership
         -t   Ignore file date/time
         -z   Don't ignore zero sized files
         -i <min size>
              Ignore files smaller than or equal <min size>
         -x <max size>
              Ignore files larger than <max size>
         -q   Don't print anything but errors/warnings
         -v   Verbose output
         -n   Dry run (don't change anything)
         -c <db file>
              Db for caching hash values
         -e <tempd dir>
              Temporary directory for data collection (use ram if not specified)
";
}

1;