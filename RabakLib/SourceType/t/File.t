use strict;
use Test;

#BEGIN { plan tests => 5, onfail => sub { exit 1; } };
BEGIN { plan tests => 19 };
#BEGIN { plan };

#use RabakLib::SourceType::File;
use RabakLib::Path::Source;
use RabakLib::Set;
use RabakLib::Conf;
use RabakLib::Log;
use File::Temp ();
use Data::Dumper;
use FindBin qw($Bin);

print "# Testing 'RabakLib::SourceType::File'\n";

# modify bin directory for including
$Bin.= "/../../..";

my $sSourceDir= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
ok -d $sSourceDir, 1, "Creating temporary source directory";

my $sTmpDirMount= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
ok -d $sTmpDirMount, 1, "Creating temporary directory";

#my $oRootConf;
my $oRootConf= RabakLib::Conf->new('testconfig');
ok ref $oRootConf, 'RabakLib::Conf', 'Creating root Conf object';
$oRootConf->set_values({
    "switch.logging" => 1,
    "switch.verbose" => 6,
});

my $oSetConf= RabakLib::Conf->new('bakset', $oRootConf);
$oRootConf->set_value('bakset', $oSetConf);
$oSetConf->set_values({
    title => "Test BakSet",
    source => "&source_file",
    target => "&target",
});

my $oSourceConf= RabakLib::Conf->new('source_file', $oRootConf);
$oRootConf->set_value('source_file', $oSourceConf);
$oSourceConf->set_values({
    type => "file",
    path => $sSourceDir,
    mount => "&source_file_mount",
});

my $oMountConf= RabakLib::Conf->new('source_file_mount', $oRootConf);
$oRootConf->set_value('source_file_mount', $oMountConf);
$oMountConf->set_values({
    device => "$Bin/test-data/dev.source",
    directory => $sSourceDir,
});

my $oSet= RabakLib::Set->CloneConf($oSetConf);
ok ref $oSet, 'RabakLib::Set', 'Creating bak set';
####################################################
# test source factory
my $oSource= RabakLib::Path::Source->Factory($oSourceConf);
ok ref $oSource, 'RabakLib::SourceType::File', 'Creating file source';

####################################################
# test moutning
my @oMountObjects= $oSource->getMountObjects();
ok @oMountObjects, 1, 'Getting Mount objects';

skip (
    $> ? "You have to be root to check mounting" : 0,       # >?
    sub{$oMountObjects[0]->mount($oSource);}, 1, "Checking mounting"
);

####################################################
# test filter-routines

sub joinFilter {
    my @sFilter= @_;
    my $sFilter= "[" . join('][', @sFilter) . "]";
    # remove comments
    $sFilter=~ s/\[\#[^\]]+\]//g;
    return $sFilter;
}

$oSource->set_value("exclude", "$sSourceDir/zuppi");
my @sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter('- /zuppi'), 'correct filter generated from exclude';

$oSource->set_value("exclude", "$sSourceDir/zuppi1 $sSourceDir/zuppi2/, $sSourceDir/zuppi3");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '- /zuppi1',
    '- /zuppi2/***',
    '- /zuppi3',
), 'correct filter generated from exclude';

$oSource->set_value("exclude", undef);
$oSource->set_value("include", "$sSourceDir/zuppi");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi',
), 'correct filter generated from include';

$oSource->set_value("include", "$sSourceDir/zuppi/zuppi1 $sSourceDir/zuppi2/, $sSourceDir/zuppi3");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zuppi/',
    '+ /zuppi/zuppi1',
    '+ /zuppi2/',
    '+ /zuppi2/**',
    '+ /zuppi3',
), 'correct filter generated from include';

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
), 'correct filter generated from filter with expansion';

$oSource->set_value("filter", "+$sSourceDir/zu\\ ppi/");
@sFilter= $oSource->_get_filter();
ok joinFilter(@sFilter), joinFilter(
    '+ /',
    '+ /zu ppi/',
    '+ /zu ppi/**',
), 'correct filter generated from filter with spaces';

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
), 'correct filter generated from exclude (inherited)';

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
), 'correct filter generated from exclude/include (inherited)';

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
), 'correct filter generated from filter (inherited)';

####################################################
# fill source data

$oSource->mkdir('zappi');
ok $oSource->isDir('zappi'), 1, 'Creating data dir in source';
$oSource->echo('zappi/zuppi1', "some data");
ok $oSource->cat('zappi/zuppi1'), "some data\n", 'Writing data to source';

skip (
    $> ? "You have to be root to check unmounting" : 0,       # >?
    sub{$oMountObjects[0]->unmount();}, 1, "Checking unmount"
);


