#!/usr/bin/perl
use strict;
use Test::Harness qw(&runtests $verbose);
use File::Temp;
use FindBin qw($Bin);


# create and remove test devices for every test script
BEGIN {`sh "$Bin/stuff/testdev-make" 2>/dev/null`;}
END {`sh "$Bin/stuff/testdev-remove" 2>/dev/null`;}

# $verbose= 1;

runtests(
    "RabakLib/t/Conf.t",
    "RabakLib/t/Path.t",
    "RabakLib/Path/t/Target.t",
    "RabakLib/SourceType/t/File.t",
);

