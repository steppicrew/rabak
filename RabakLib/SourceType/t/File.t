use strict;
use Test;

#BEGIN { plan tests => 5, onfail => sub { exit 1; } };
BEGIN { plan tests => 13 };
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

my $sTmpDir1= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
ok -d "$sTmpDir1", 1, "Creating temporary directory";

my $sTmpDirMount= File::Temp->tempdir('TESTXXXXX', CLEANUP => 1 );
ok -d "$sTmpDirMount", 1, "Creating temporary directory";

#my $oRootConf;
my $oRootConf= RabakLib::Conf->new('testconfig');
ok ref $oRootConf, 'RabakLib::Conf', 'Creating root Conf object';

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
    path => $sTmpDir1,
    mount => "&source_file_mount",
});

my $oMountConf= RabakLib::Conf->new('source_file_mount', $oRootConf);
$oRootConf->set_value('source_file_mount', $oMountConf);
$oMountConf->set_values({
    device => "/dev/hd* /dev/sd*",
    directory => $sTmpDirMount,
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
    $> ? "You have to be root to check mounting" : 0,
    sub {
        my $iResult= $oMountObjects[0]->mount($oSource);
        $oMountObjects[0]->unmount() if $iResult;
        $iResult; 
    }, 1, "Checking mounting"
);

####################################################
# test filter-routines
$oSource->set_value("exclude", "$sTmpDir1/zuppi");
my @sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '- /zuppi', 'correct filter generated from exclude';

$oSource->set_value("exclude", "$sTmpDir1/zuppi1 $sTmpDir1/zuppi2/, $sTmpDir1/zuppi3");
@sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '- /zuppi1][- /zuppi2/***][- /zuppi3', 'correct filter generated from exclude';

$oSource->set_value("exclude", undef);
$oSource->set_value("include", "$sTmpDir1/zuppi");
@sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '+ /][+ /zuppi', 'correct filter generated from include';

$oSource->set_value("include", "$sTmpDir1/zuppi/zuppi1 $sTmpDir1/zuppi2/, $sTmpDir1/zuppi3");
@sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '+ /][+ /zuppi/][+ /zuppi/zuppi1][+ /zuppi2/][+ /zuppi2/**][+ /zuppi3', 'correct filter generated from include';

$oSource->set_value("include", undef);
$oSource->set_value("filter", "+$sTmpDir1/(zuppi /zappi/ )/zuppi1 -($sTmpDir1/zuppi2/, $sTmpDir1/zuppi3)");
@sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '+ /][+ /zuppi/][+ /zuppi/zuppi1][+ /zappi/][+ /zappi/zuppi1][- /zuppi2/***][- /zuppi3', 'correct filter generated from filter';

$oSource->set_value("filter", "+$sTmpDir1/zu\\ ppi/");
@sFilter= $oSource->_get_filter();
ok join('][', @sFilter), '+ /][+ /zu ppi/][+ /zu ppi/**', 'correct filter generated from filter';
