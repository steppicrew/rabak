#!/usr/bin/perl
use strict;
use Test::Harness qw(&runtests $verbose);

use FindBin qw($Bin);

$verbose= 1;

`sh $Bin/stuff/testdev-make 2>/dev/null`;

runtests(
    "RabakLib/SourceType/t/File.t",
);

`sh $Bin/stuff/testdev-remove 2>/dev/null`;

