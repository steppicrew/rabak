#!/usr/bin/perl
use strict;
use Test::Harness qw(&runtests $verbose);

use FindBin qw($Bin);

#$verbose= 1;

runtests(
    "RabakLib/t/Conf.t",
    "RabakLib/Path/t/Target.t",
    "RabakLib/SourceType/t/File.t",
);

