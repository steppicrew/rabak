use strict;
use Test;

BEGIN { plan tests => 69 };

use RabakLib::Path::Mountable;
use Data::Dumper;
use FindBin qw($Bin);

print "# Testing 'RabakLib::Conf'\n";

# modify bin directory for including
$Bin.= "/../..";

my $oRootConf= require "$Bin/RabakLib/t/Common.t";
ok ref $oRootConf, 'RabakLib::Conf', 'Checking base config';

my $oTargetConf= $oRootConf->get_node("testtarget");
ok ref $oTargetConf, 'RabakLib::Conf', 'Checking target config';
ok -d $oTargetConf->get_value("path"), 1, 'Path value is a directory';
my $oPath= RabakLib::Path::Mountable->newFromConf($oTargetConf);
ok ref $oPath, 'RabakLib::Path::Mountable', 'Creating Path from Conf';

my $sOrigPath= $oPath->get_value("path");
# check getPath()
ok $oPath->getPath("test"), $oPath->getPath("$sOrigPath///./test"), 'Checking getPath()';
ok $oPath->getFullPath(), $oPath->getPath(), 'Checking if getFullPath() equals getPath() on local paths';

# checking PathBase functions
ok $oPath->abs_path("test"), "/^\//", 'Checking abs_path()';
# echo/cat
$oPath->echo("test", "some data");
ok $oPath->cat("test"), "some data\n", 'Checking echo()/cat() 1';
ok $oPath->cat("$sOrigPath/test"), "some data\n", 'Checking echo()/cat() 2';
# copy and append Loc2Rem
ok $oPath->copyLocalFileToRemote("$sOrigPath/test", "test2"), 1, "Copying local file to remote 1";
ok $oPath->cat("test2"), "some data\n", 'Checking copied data 1';
ok $oPath->copyLocalFileToRemote("$sOrigPath/test", "test2", 1), 1, "Appending local file to remote";
ok $oPath->cat("test2"), "some data\nsome data\n", 'Checking appended data';
ok $oPath->copyLocalFileToRemote("$sOrigPath/test", "test2"), 1, "Copying local file to remote 2";
ok $oPath->cat("test2"), "some data\n", 'Checking copied data 2';
# df
ok $oPath->df(), "/\%/", 'Checking df';
# checking file attributes (check with double negation to simplify result)
ok !!$oPath->mkdir("testdir"), 1, 'Creating Dir';
ok !!$oPath->isDir(), 1, 'Checking isDir()';
ok !!$oPath->isDir("/"), 1, 'Checking isDir("/")';
ok !!$oPath->isDir("test"), '', 'Checking isDir() on file';
ok !!$oPath->isDir("testdir"), 1, 'Checking isDir() on dir';
ok !!$oPath->isSymlink("test"), '', 'Checking symlink on file';
ok !!$oPath->isSymlink("testdir"), '', 'Checking symlink on dir';
ok !!$oPath->isFile(), '', 'Checking isFile()';
ok !!$oPath->isFile("/"), '', 'Checking isFile("/")';
ok !!$oPath->isFile("test"), 1, 'Checking isFile() on file';
ok !!$oPath->isReadable(), 1, 'Checking isReadable()';
ok !!$oPath->isReadable("/"), 1, 'Checking isReadable("/")';
ok !!$oPath->isReadable("test"), 1, 'Checking isReadable() on file';
ok !!$oPath->isWritable(), 1, 'Checking isWritable()';
ok !!$oPath->isWritable("/"), 1, 'Checking isWritable("/")';
ok !!$oPath->isWritable("test"), 1, 'Checking isWritable() on file';
chmod 0000, "$sOrigPath/test2";
skip $> ? '' : 'isReadable cannot be checked as user root', !!$oPath->isReadable("test2"), '', 'Checking isReadable() on file without rights';
skip $> ? '' : 'isWritable cannot be checked as user root',  !!$oPath->isWritable("test2"), '', 'Checking isWritable() on file without rights';
ok !!$oPath->isDir("test3"), '', 'Checking isDir() on nonextant file';
ok !!$oPath->isFile("test3"), '', 'Checking isFile() on nonextant file';
ok !!$oPath->isReadable("test3"), '', 'Checking isReadable() on nonextant file';
ok !!$oPath->isWritable("test3"), '', 'Checking isWritable() on nonextant file';

ok !!$oPath->symlink("test", "test3"), 1, 'Creating symlink';
ok !!$oPath->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPath->isDir("test3"), '', 'Checking isDir() on symlink';
ok !!$oPath->isFile("test3"), 1, 'Checking isFile() on symlink';
ok !!$oPath->isReadable("test3"), 1, 'Checking isReadable() on symlink';
ok !!$oPath->isWritable("test3"), 1, 'Checking isWritable() on symlink';
ok !!$oPath->unlink("test3"), 1, 'Deleting symlink';
ok !!$oPath->symlink("test2", "test3"), 1, 'Creating symlink';
ok !!$oPath->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPath->isDir("test3"), '', 'Checking isDir() on symlink';
ok !!$oPath->isFile("test3"), 1, 'Checking isFile() on symlink';
skip $> ? '' : 'isReadable cannot be checked as user root',  !!$oPath->isReadable("test3"), '', 'Checking isReadable() on symlink';
skip $> ? '' : 'isWritable cannot be checked as user root',  !!$oPath->isWritable("test3"), '', 'Checking isWritable() on symlink';
ok !!$oPath->unlink("test3"), 1, 'Deleting symlink';
ok !!$oPath->symlink(".", "test3"), 1, 'Creating symlink';
ok !!$oPath->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPath->isDir("test3"), 1, 'Checking isDir() on symlink';
ok !!$oPath->isFile("test3"), '', 'Checking isFile() on symlink';
ok !!$oPath->isReadable("test3"), 1, 'Checking isReadable() on symlink';
ok !!$oPath->isWritable("test3"), 1, 'Checking isWritable() on symlink';
# getDir()
chmod 0777, "$sOrigPath/test2";
my @sDir= sort $oPath->getDir();
my @sExpectedDir= sort("$sOrigPath/test", "$sOrigPath/test2", "$sOrigPath/test3", "$sOrigPath/testdir");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking getDir()';
@sDir= sort $oPath->glob("$sOrigPath/*");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking glob()';
@sDir= sort $oPath->getDir(undef, 1);
@sExpectedDir= sort("$sOrigPath/test#", "$sOrigPath/test2*", "$sOrigPath/test3@", "$sOrigPath/testdir/");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking getDir() with file type';
# getDirRecursive()
my %sDir= $oPath->getDirRecursive();
my %sExpectedDir= (
    "$sOrigPath/test" => "",
    "$sOrigPath/test2" => "",
    "$sOrigPath/test3" => ".",
    "$sOrigPath/testdir" => {},
);
for my $sKey (keys %sDir) {
    if (ref $sDir{$sKey}) {
        ok Dumper($sDir{$sKey}), Dumper($sExpectedDir{$sKey}), "Comparing \$sDir{$sKey} with \$sExpectesDir{$sKey}";
    }
    else {
        ok $sDir{$sKey}, $sExpectedDir{$sKey}, "Comparing \$sDir{$sKey} with \$sExpectesDir{$sKey}";
    }
}
for my $sKey (keys %sExpectedDir) {
    if (ref $sExpectedDir{$sKey}) {
        ok Dumper($sExpectedDir{$sKey}), Dumper($sDir{$sKey}), "Comparing \$sExpectedDir{$sKey} with \$sDir{$sKey}";
    }
    else {
        ok $sExpectedDir{$sKey}, $sDir{$sKey}, "Comparing \$sExpectedDir{$sKey} with \$sDir{$sKey}";
    }
}

# TODO: mount/unmount/tempfile/tempdir/rmtree
