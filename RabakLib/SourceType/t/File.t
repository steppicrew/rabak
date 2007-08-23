use strict;
use Test;

#BEGIN { plan tests => 5, onfail => sub { exit 1; } };
BEGIN { plan tests => 6 };
#BEGIN { plan };

#use RabakLib::SourceType::File;
use RabakLib::Path::Source;
use RabakLib::Conf;
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

my $oSource= RabakLib::Path::Source->Factory($oSourceConf);
ok ref $oSource, 'RabakLib::SourceType::File', 'Creating file source';

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
