#!/usr/bin/perl
use strict;
use Test::Harness qw(&runtests $verbose);
use File::Temp;
use FindBin qw($Bin);

# Tests may fail if not run as root or in vserver


# create and remove test devices for every test script
BEGIN {`sh "$Bin/../share/stuff/testdev-make" 2>/dev/null`;}
END {`sh "$Bin/../share/stuff/testdev-remove" 2>/dev/null`;}

$verbose= 1;

runtests(
    "$Bin/RabakLib/Conf.t",
    "$Bin/RabakLib/Peer.t",
    "$Bin/RabakLib/Peer/Target.t",
    "$Bin/RabakLib/Peer/Source/File.t",
);

