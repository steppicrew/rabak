#!/usr/bin/perl

# See License.txt for licence

use warnings;
use strict;

# Comment out when not debugging
use Carp ();
local $SIG{__WARN__} = \&Carp::cluck;
local $SIG{__DIE__} = \&Carp::cluck;

umask 0077; # make sure all tempfiles are readable only by us

use Cwd;
use Data::Dumper;
use Getopt::Std;

use RabakLib::Cmd;

my $VERSION= "1.0_rc5";
my $DEBUG= 0;

my $oCmd= RabakLib::Cmd::Build(\@ARGV);
print $oCmd->error() . $/ unless $oCmd->run();

# if ($oCmd->{ERROR}) {
#     print "Error: " . $oCmd->{ERROR} . "\n";
# }

1;
