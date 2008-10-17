#!/usr/bin/perl
use strict;
use Test::Harness qw(&runtests $verbose);
use File::Temp;
use FindBin qw($Bin);

# Tests may fail if not run as root or in vserver


# create and remove test devices for every test script
BEGIN {`sh "$Bin/stuff/testdev-make" 2>/dev/null`;}
END {`sh "$Bin/stuff/testdev-remove" 2>/dev/null`;}

$verbose= 1;

runtests(
    "RabakLib/t/Conf.t",
    "RabakLib/t/Peer.t",
    "RabakLib/Peer/t/Target.t",
    "RabakLib/Peer/Source/t/File.t",
);

