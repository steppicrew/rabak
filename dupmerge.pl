#!/usr/bin/perl

# Merge duplicate files

# This is work in progress. It should work fine but it lacks proper
# integration with rabak. Coming soon...

use strict;
use Getopt::Std;
use Data::Dumper;

use DupMerge::DupMerge;

$Getopt::Std::STANDARD_HELP_VERSION= 1;
my %opts= ();

getopts("hdpotvnzi:x:w:qb:m:a:", \%opts) or die HELP_MESSAGE();

my @sDirectories= @ARGV;
my $dm= DupMerge::DupMerge->new();

$dm->run(\@sDirectories, {
    temp_dir        => $opts{w},
    base_dir        => $opts{a},
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
    db_engine       => $opts{b},
    multi_db_postfix=> $opts{m},
    
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
         -b <db engine>
              database engine. possible values: sqlite2, sqlite3 (default)
         -w <temp dir>
              Working directory for temporary data collection (default: '/tmp')
         -a <base dir>
              directory for inodes.db (default: current dir)
         -m <multi db postfix>
              Enables db for each directory. Specifies postfix for db name
";
}

1;