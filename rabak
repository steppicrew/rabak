#!/usr/bin/perl

# See License.txt for licence

use warnings;
use strict;

# Comment out when not debugging
use Carp ();
local $SIG{__WARN__} = \&Carp::cluck;
local $SIG{__DIE__} = \&Carp::cluck;

use RabakLib::Cmd;

my $oCmd= RabakLib::Cmd::Build(\@ARGV);
print $oCmd->error() . $/ unless $oCmd->run();

1;
