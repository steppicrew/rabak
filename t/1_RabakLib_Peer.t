#!/usr/bin/perl

use strict;
use Test;

BEGIN { plan tests => 69 };

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Rabak::Peer::Target;
use Data::Dumper;

print "# Testing 'Rabak::Conf'\n";

my $oRootConf= require "$Bin/Common.pm";
ok ref $oRootConf, 'Rabak::Conf', 'Checking base config';

my $oTargetConf= $oRootConf->get_node("testtarget");
ok ref $oTargetConf, 'Rabak::Conf', 'Checking target config';
ok -d $oTargetConf->get_value("path"), 1, 'Path value is a directory';
# we have to instanciate Rabak::Peer::Target to get a mountable Peer (getPath() behaves differently)
my $oPeer= Rabak::Peer::Target->newFromConf($oTargetConf);
ok ref $oPeer, 'Rabak::Peer::Target', 'Creating Target Peer from Conf';

my $sOrigPath= $oPeer->getPath();
# check getPath()
ok $oPeer->getPath("test"), $oPeer->getPath("$sOrigPath///./test"), 'Checking getPath()';
ok $oPeer->getFullPath(), $oPeer->getPath(), 'Checking if getFullPath() equals getPath() on local paths';

# checking PathBase functions
ok $oPeer->abs_path("test"), "/^\//", 'Checking abs_path()';
# echo/cat
$oPeer->echo("test", "some data");
ok $oPeer->cat("test"), "some data\n", 'Checking echo()/cat() 1';
ok $oPeer->cat("$sOrigPath/test"), "some data\n", 'Checking echo()/cat() 2';
# copy and append Loc2Rem
ok $oPeer->copyLocalFileToRemote("$sOrigPath/test", "test2"), 1, "Copying local file to remote 1";
ok $oPeer->cat("test2"), "some data\n", 'Checking copied data 1';
ok $oPeer->copyLocalFileToRemote("$sOrigPath/test", "test2", 1), 1, "Appending local file to remote";
ok $oPeer->cat("test2"), "some data\nsome data\n", 'Checking appended data';
ok $oPeer->copyLocalFileToRemote("$sOrigPath/test", "test2"), 1, "Copying local file to remote 2";
ok $oPeer->cat("test2"), "some data\n", 'Checking copied data 2';
# df
ok $oPeer->df(), "/\%/", 'Checking df';
# checking file attributes (check with double negation to simplify result)
ok !!$oPeer->mkdir("testdir"), 1, 'Creating Dir';
ok !!$oPeer->isDir(), 1, 'Checking isDir()';
ok !!$oPeer->isDir("/"), 1, 'Checking isDir("/")';
ok !!$oPeer->isDir("test"), '', 'Checking isDir() on file';
ok !!$oPeer->isDir("testdir"), 1, 'Checking isDir() on dir';
ok !!$oPeer->isSymlink("test"), '', 'Checking symlink on file';
ok !!$oPeer->isSymlink("testdir"), '', 'Checking symlink on dir';
ok !!$oPeer->isFile(), '', 'Checking isFile()';
ok !!$oPeer->isFile("/"), '', 'Checking isFile("/")';
ok !!$oPeer->isFile("test"), 1, 'Checking isFile() on file';
ok !!$oPeer->isReadable(), 1, 'Checking isReadable()';
ok !!$oPeer->isReadable("/"), 1, 'Checking isReadable("/")';
ok !!$oPeer->isReadable("test"), 1, 'Checking isReadable() on file';
ok !!$oPeer->isWritable(), 1, 'Checking isWritable()';
ok !!$oPeer->isWritable("/"), $> ? '' : 1, 'Checking isWritable("/")';
ok !!$oPeer->isWritable("test"), 1, 'Checking isWritable() on file';
chmod 0000, "$sOrigPath/test2";
skip $> ? '' : 'isReadable cannot be checked as user root', !!$oPeer->isReadable("test2"), '', 'Checking isReadable() on file without rights';
skip $> ? '' : 'isWritable cannot be checked as user root',  !!$oPeer->isWritable("test2"), '', 'Checking isWritable() on file without rights';
ok !!$oPeer->isDir("test3"), '', 'Checking isDir() on nonextant file';
ok !!$oPeer->isFile("test3"), '', 'Checking isFile() on nonextant file';
ok !!$oPeer->isReadable("test3"), '', 'Checking isReadable() on nonextant file';
ok !!$oPeer->isWritable("test3"), '', 'Checking isWritable() on nonextant file';

ok !!$oPeer->symlink("test", "test3"), 1, 'Creating symlink';
ok !!$oPeer->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPeer->isDir("test3"), '', 'Checking isDir() on symlink';
ok !!$oPeer->isFile("test3"), 1, 'Checking isFile() on symlink';
ok !!$oPeer->isReadable("test3"), 1, 'Checking isReadable() on symlink';
ok !!$oPeer->isWritable("test3"), 1, 'Checking isWritable() on symlink';
ok !!$oPeer->unlink("test3"), 1, 'Deleting symlink';
ok !!$oPeer->symlink("test2", "test3"), 1, 'Creating symlink';
ok !!$oPeer->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPeer->isDir("test3"), '', 'Checking isDir() on symlink';
ok !!$oPeer->isFile("test3"), 1, 'Checking isFile() on symlink';
skip $> ? '' : 'isReadable cannot be checked as user root',  !!$oPeer->isReadable("test3"), '', 'Checking isReadable() on symlink';
skip $> ? '' : 'isWritable cannot be checked as user root',  !!$oPeer->isWritable("test3"), '', 'Checking isWritable() on symlink';
ok !!$oPeer->unlink("test3"), 1, 'Deleting symlink';
ok !!$oPeer->symlink(".", "test3"), 1, 'Creating symlink';
ok !!$oPeer->isSymlink("test3"), 1, 'Checking symlink';
ok !!$oPeer->isDir("test3"), 1, 'Checking isDir() on symlink';
ok !!$oPeer->isFile("test3"), '', 'Checking isFile() on symlink';
ok !!$oPeer->isReadable("test3"), 1, 'Checking isReadable() on symlink';
ok !!$oPeer->isWritable("test3"), 1, 'Checking isWritable() on symlink';
# getDir()
chmod 0777, "$sOrigPath/test2";
my @sDir= sort $oPeer->getDir();
my @sExpectedDir= sort("$sOrigPath/test", "$sOrigPath/test2", "$sOrigPath/test3", "$sOrigPath/testdir");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking getDir()';
@sDir= sort $oPeer->glob("$sOrigPath/*");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking glob()';
@sDir= sort $oPeer->getDir(undef, 1);
@sExpectedDir= sort("$sOrigPath/test#", "$sOrigPath/test2*", "$sOrigPath/test3@", "$sOrigPath/testdir/");
ok "[".join("][", @sDir), "[".join("][", @sExpectedDir), 'Checking getDir() with file type';
# getDirRecursive()
my %sDir= $oPeer->getDirRecursive();
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
