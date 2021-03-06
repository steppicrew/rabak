#!/usr/bin/perl

use strict;
use Test;

BEGIN { plan tests => 44 };

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Rabak::Peer::Target;
use Rabak::Set;
use Data::Dumper;

print "# Testing 'Rabak::Peer::Target'\n";

my $oRootConf= require "$Bin/Common.pm";
ok ref $oRootConf, 'Rabak::Conf', 'Checking base config';

my $oSetConf= $oRootConf->get_node("testbakset");
ok ref $oSetConf, 'Rabak::Conf', 'Checking bakset config';
my $oSet= Rabak::Set->newFromConf($oSetConf);
ok ref $oSet, 'Rabak::Set', 'Creating bak set from Conf';
####################################################
# test target creation
my $oTargetConf= $oRootConf->get_node("testtarget");
ok ref $oTargetConf, 'Rabak::Conf', 'Checking target config';
ok -d $oTargetConf->get_value("path"), 1, 'Target path is a directory';
my $oTarget= Rabak::Peer::Target->newFromConf($oTargetConf);
ok ref $oTarget, 'Rabak::Peer::Target', 'Creating Target from Conf';

####################################################
# mounting and unmounting

my @oMounts= $oTarget->mountable()->getMountObjects();
ok @oMounts, 1, 'Getting MountObjects';
my $aMessages= [];
skip (
    skipRoot("check mounting"),
    sub{$oMounts[0]->mount($oTarget, $aMessages);}, 1, "Checking Target mounting"
);
skip (
    skipRoot("check unmounting"),
    sub{$oMounts[0]->unmount(undef, $aMessages);}, 1, "Checking Target unmounting"
);
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting"
);
####################################################
# targetgroup
$oTarget->set_value('group', 'zuppi');
skip (
    skipRoot("check mounting"),
    sub{$oTarget->mountable()->mountAll($aMessages);}, 0, "Checking direct Target mounting (group 'zuppi')"
);
$oTarget->set_value('group', 'dayofweek');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting (group 'dayofweek')"
);

$oTarget->set_value('switch.targetvalue', 'XXX');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 0, "Checking direct Target mounting (group 'dayofweek' with wrong targetvalue)"
);
$oTarget->set_value('switch.targetvalue', 'Mon');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting (group 'dayofweek' with targetvalue 'Mon')"
);
$oTarget->set_value('switch.targetvalue', 'Tue');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting (group 'dayofweek' with targetvalue 'Tue')"
);

####################################################
# no rabak.dev.cf
$oTarget->set_value('mount', 'testsource_file_mount');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 0, "Checking direct Target mounting (not target device)"
);

####################################################
# wrong mount reference
$oTarget->set_value('mount', 'non_existant');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 0, "Checking direct Target mounting (nonexistant dir/device)"
);
# TODO: check error in log
$oTarget->set_value('mount', '&non_existant');
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting (nonexistant reference)"
);

####################################################
# no mount reference
$oTarget->set_value('mount', undef);
skip (
    skipRoot("check mounting"),
    sub{
        my $iResult= $oTarget->mountable()->mountAll($aMessages);
        $oTarget->mountable()->unmountAll($aMessages) if $iResult;
        $iResult;
    }, 1, "Checking direct Target mounting (no refrence)"
);

####################################################
# testing remove_old()
my @sBakDirs= ();
# build dirs beneath target path, every 2nd dir is empty (and should be removed)
for my $i (1..6) {
    my $sDir= "dir$i";
    push @sBakDirs, $sDir;
    $oTarget->mkdir($sDir);
    # check for creation at absolute path
    ok $oTarget->isDir($sDir), 1, "$sDir should exist";
    next if $i % 2;
    $oTarget->echo("$sDir/data", "some data");
    ok $oTarget->isFile("$sDir/data"), 1, "$sDir/data should exist";
}
# add paths NOT beneath target
my $sExtDir1= $oTarget->tempdir();
$oTarget->mkdir($sExtDir1);
unshift @sBakDirs, $sExtDir1; 
my $sExtDir2= $oTarget->tempdir();
$oTarget->mkdir($sExtDir2);
push @sBakDirs, $sExtDir2; 

$oTarget->{SOURCE_DATA}{OLD_BAKDIRS}= \@sBakDirs;
# first remove no dirs
$oTarget->{SOURCE_DATA}{KEEP}= 0;
$oTarget->remove_old();
# no dir should be deleted
for my $sDir (@sBakDirs) {
    ok $oTarget->isDir("$sDir"), 1, "'$sDir' should not have been deleted";
}
# now remove all but first two nonempty dirs
$oTarget->{SOURCE_DATA}{KEEP}= 2;
$oTarget->remove_old();
# external dirs should never be deleted
ok $oTarget->isDir($sExtDir1), 1, "$sExtDir1 should not have been deleted";
ok $oTarget->isDir($sExtDir2), 1, "$sExtDir2 should not have been deleted";
# first two nonempty dirs should not be deleted
for my $i (2, 4) {
    ok $oTarget->isDir("dir$i"), 1, "Dir$i should not have been deleted";
}
# all other dirs should be removed
for my $i (1, 3, 5, 6) {
    ok $oTarget->isDir("dir$i"), undef, "Dir$i should have been deleted";
}

