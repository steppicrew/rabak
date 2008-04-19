#!/usr/bin/perl

use strict;
use File::Temp;
use RabakLib::Conf;
use FindBin qw($Bin);

# common include file for tests, creating base config structure
# does not run any tests (cause "plan" can called only once)

# create and remove test devices for every test script
BEGIN {`sh $Bin/stuff/testdev-make 2>/dev/null`;}
END {`sh $Bin/stuff/testdev-remove 2>/dev/null`;}

my $sSourceDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
my $sTargetDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );

#my $sSourceDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 0 );
#my $sTargetDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 0 );

#my $sSourceMountDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
#my $sTargetMountDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );

my $oRootConf= RabakLib::Conf->new('testconfig');
$oRootConf->preset_values({
    "switch.logging" => 0,
    "switch.verbose" => 0,
});

return undef unless $oRootConf;

my $oSetConf= RabakLib::Conf->new('testbakset', $oRootConf);
$oRootConf->set_value('testbakset', $oSetConf);
$oSetConf->preset_values({
    title => "Test BakSet",
    source => "&testsource_file",
    target => "&testtarget",
});

my $oSourceConf= RabakLib::Conf->new('testsource_file', $oRootConf);
$oRootConf->set_value('testsource_file', $oSourceConf);
$oSourceConf->preset_values({
    type => "file",
    path => $sSourceDir,
    mount => "&testsource_file_mount",
});

my $oTargetConf= RabakLib::Conf->new('testtarget', $oRootConf);
$oRootConf->set_value('testtarget', $oTargetConf);
$oTargetConf->preset_values({
    path => $sTargetDir,
    mount => "&testtarget_mount",
});

my $oSourceMountConf= RabakLib::Conf->new('testsource_file_mount', $oRootConf);
$oRootConf->set_value('testsource_file_mount', $oSourceMountConf);
$oSourceMountConf->preset_values({
    device => "/tmp/rabak-sample-data/dev.source",
    directory => $sSourceDir,
});

my $oTargetMountConf= RabakLib::Conf->new('testtarget_mount', $oRootConf);
$oRootConf->set_value('testtarget_mount', $oTargetMountConf);
$oTargetMountConf->preset_values({
    device => "/tmp/rabak-sample-data/test-data/dev.loop?",
    directory => $sTargetDir,
});

$oRootConf;