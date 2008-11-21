#!/usr/bin/perl

use strict;
use Test;

BEGIN { plan tests => 45 };

use FindBin qw($Bin);
use lib "$Bin/../../../../lib";
use RabakLib::Peer::Source;
use RabakLib::Set;
use Data::Dumper;

print "# Testing 'RabakLib::Peer::Source::File'\n";

# TODO: test remote sources (dont know how to)

$Bin.= "/../..";

my $oRootConf= require "$Bin/Common.t";
ok ref $oRootConf, 'RabakLib::Conf', 'Checking base config';

my $oSetConf= $oRootConf->get_node("testbakset");
ok ref $oSetConf, 'RabakLib::Conf', 'Checking bakset config';
my $oSet= RabakLib::Set->newFromConf($oSetConf);
ok ref $oSet, 'RabakLib::Set', 'Creating bak set from Conf';
####################################################
# test source factory
my $oSourceConf= $oRootConf->get_node("testsource_file");
ok ref $oSourceConf, 'RabakLib::Conf', 'Checking source config';
ok -d $oSourceConf->get_value("path"), 1, 'Source path is a directory';
my $oSource= RabakLib::Peer::Source->Factory($oSourceConf);
ok ref $oSource, 'RabakLib::Peer::Source::File', 'Creating file source from Conf';

####################################################
# test filter-routines

sub joinFilter {
    my @sFilter= @_;
    my $sFilter= "[" . join('][', @sFilter) . "]";
    # remove comments
    $sFilter=~ s/\[\#[^\]]+\]//g;
    return $sFilter;
}

my $sSourceDir= $oSource->get_value("path");
$oSource->set_value("exclude", "$sSourceDir/zuppi");
my @sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter('- /zuppi'), 'correct filter generated from exclude';

$oSource->set_value("exclude", "$sSourceDir/zuppi1 $sSourceDir/zuppi2/, $sSourceDir/zuppi3");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '- /zuppi1',
    '- /zuppi2/***',
    '- /zuppi3',
), 'Filter generated from exclude';

$oSource->set_value("exclude", undef);
$oSource->set_value("include", "$sSourceDir/zuppi");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi',
), 'Filter generated from include';

$oSource->set_value("include", "$sSourceDir/zuppi/zuppi1 $sSourceDir/zuppi2/, $sSourceDir/zuppi3");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi/',
    '+ /zuppi/zuppi1',
    '+ /zuppi2/',
    '+ /zuppi2/**',
    '+ /zuppi3',
), 'Filter generated from include';

$oSource->set_value("include", undef);
$oSource->set_value("filter", "+$sSourceDir/(zuppi /zappi/ )/zuppi1 -($sSourceDir/zuppi2/, $sSourceDir/zuppi3)");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi/',
    '+ /zuppi/zuppi1',
    '+ /zappi/',
    '+ /zappi/zuppi1',
    '- /zuppi2/***',
    '- /zuppi3',
), 'Filter generated from filter with expansion';

$oSource->set_value("filter", "+$sSourceDir/zu\\ \\(\\{ppi/");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zu ({ppi/',
    '+ /zu ({ppi/**',
), 'Filter generated from filter with spaces and special chars';

$oRootConf->set_value('source_file_exclude', "$sSourceDir/zuppi1 $sSourceDir/zuppi2/, $sSourceDir/zuppi3");
$oRootConf->set_value('source_file_include', "$sSourceDir/zappi/(zuppi1 /zuppi2/, /zuppi3)");
$oRootConf->set_value('source_file_filter', "+&source_file_exclude -&source_file_include");

$oSource->set_value("filter", undef);
$oRootConf->set_value('exclude', '&source_file_exclude');
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '- /zuppi1',
    '- /zuppi2/***',
    '- /zuppi3',
), 'Filter generated from exclude (inherited)';

$oRootConf->set_value('include', '&source_file_include');
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '- /zuppi1',
    '- /zuppi2/***',
    '- /zuppi3',
    '+ /',
    '+ /zappi/',
    '+ /zappi/zuppi1',
    '+ /zappi/zuppi2/',
    '+ /zappi/zuppi2/**',
    '+ /zappi/zuppi3',
), 'Filter generated from exclude/include (inherited)';

$oRootConf->set_value('include', undef);
$oRootConf->set_value('exclude', undef);
$oRootConf->set_value('filter', '&source_file_filter');
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi1',
    '+ /zuppi2/',
    '+ /zuppi2/**',
    '+ /zuppi3',
    '- /zappi/zuppi1',
    '- /zappi/zuppi2/***',
    '- /zappi/zuppi3',
), 'Filter generated from filter (inherited)';

$oSource->set_value('filter', '&filter');
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter('# '), 'Recursion detection in filter parsing';

$oSource->set_value('filter', '&.filter');
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi1',
    '+ /zuppi2/',
    '+ /zuppi2/**',
    '+ /zuppi3',
    '- /zappi/zuppi1',
    '- /zappi/zuppi2/***',
    '- /zappi/zuppi3',
), 'Filter references';

####################################################
# create target

my $oTarget= $oSet->get_targetPeer();
ok ref $oTarget, 'RabakLib::Peer::Target', 'Retrieving target from bakset';
ok -d $oTarget->get_value("path"), 1, 'Target path is a directory';

####################################################
# test moutning
my @oSourceMountObjects= $oSource->mountable()->getMountObjects();
ok @oSourceMountObjects, 1, 'Getting Mount objects from Source';
ok -d $oSourceMountObjects[0]->get_value("directory"), 1, 'Source Mount directory is a directory';

skip (
    $> ? "You have to be root to check mounting" : 0,       # >?
    sub{$oSourceMountObjects[0]->mount($oSource);}, 1, "Checking Source mounting"
);

my @oTargetMountObjects= $oTarget->mountable()->getMountObjects();
ok @oTargetMountObjects, 1, 'Getting Mount objects from Target';
ok -d $oTargetMountObjects[0]->get_value("directory"), 1, 'Target Mount directory is a directory';

skip (
    $> ? "You have to be root to check mounting" : 0,       # >?
    sub{$oTargetMountObjects[0]->mount($oTarget);}, 1, "Checking Target mounting"
);

####################################################
# fill source data
sub mk_testdir {
    my $sDir= shift;
    $oSource->mkdir($sDir);
    ok $oSource->isDir($sDir), 1, "Creating dir '$sDir' in source";
}
sub mk_testfile {
    my $sFile= shift;
    my $sData= shift || "some data";
    $oSource->echo($sFile, $sData);
    ok $oSource->cat($sFile), "$sData\n", "Writing text to '$sFile' on source";
}

$oSource->set_value('filter', "$sSourceDir(+/zuppi/transfer -/zuppi/ +/zappi/transfer* -/zappi/* -/)");
mk_testfile('this_should_bot_be_saved');
mk_testdir('zuppi');
mk_testfile('zuppi/transfer');
mk_testfile('zuppi/dont_transfer');
mk_testdir('zappi');
mk_testfile('zappi/transfer');
mk_testfile('zappi/transfer_this_too');
mk_testfile('zappi/dont_transfer_this');

####################################################
# run backup
my $sFullTarget= $oTarget->getPath() . "/setdir/daydir/";
$oTarget->mkdir('setdir');
$oTarget->mkdir('setdir/daydir');
ok $oTarget->isDir($sFullTarget), 1, "Creating dir '$sFullTarget' in target";
$oTarget->{SOURCE_DATA}{OLD_BAKDIRS}= [];
$oTarget->{SOURCE_DATA}{BAKDIR}= $sFullTarget;
my $iRunResult= $oSource->run($oTarget);
ok $iRunResult, 0, 'Running backup';

####################################################
# test source files on target
sub target_testdir {
    my $sDir= shift;
    ok $oTarget->isDir("$sFullTarget/$sDir"), 1, "Source dir '$sDir' created on Target";
}
sub target_testfile {
    my $sFile= shift;
    my $iResult= shift;
    ok $oTarget->isFile("$sFullTarget/$sFile"), $iResult, "Source file '$sFile' created on Target";
}
target_testfile "this_should_bot_be_saved", undef;
target_testdir "zuppi", 1;
target_testfile "zuppi/transfer", 1;
target_testfile "zuppi/dont_transfer", undef;
target_testdir "zappi", 1;
target_testfile "zappi/transfer", 1;
target_testfile "zappi/transfer_this_too", 1;
target_testfile "zappi/dont_transfer_this", undef;

####################################################
# unmounting
skip (
    $> ? "You have to be root to check unmounting" : 0,       # >?
    sub{$oTargetMountObjects[0]->unmount();}, 1, "Checking Target unmount"
);

skip (
    $> ? "You have to be root to check unmounting" : 0,       # >?
    sub{$oSourceMountObjects[0]->unmount();}, 1, "Checking Source unmount"
);


