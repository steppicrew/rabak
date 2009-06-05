#!/usr/bin/perl

use strict;
use warnings;

use SSH;

`rm out.txt`;

my $ssh= SSH->new();
print "1\n";
$ssh->run("zuppi\n");
$ssh->run("zappi\n");
