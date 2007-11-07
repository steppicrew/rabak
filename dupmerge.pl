#!/usr/bin/perl

use strict;
use Getopt::Std;
use File::Find;
use Data::Dumper;
use Fcntl ':mode';
use Digest::SHA1;
use DBI;

use DupMerge::DataStore;

$Getopt::Std::STANDARD_HELP_VERSION= 1;
my %opts= ();

getopts("hdpotvnc:zi:x:e:q", \%opts) or die HELP_MESSAGE();

$|= 1;

my @sDirectories= @ARGV;
my $sDev= undef;
my $cache_dbh= undef;
my $ds= undef;

my %stats= ();

if ($opts{c}) {
    print "Using file '$opts{c}' for digest caching.\n" unless $opts{q};
    eval {
        my $cache_dbfile= $opts{c};
        $cache_dbh = DBI->connect("dbi:SQLite2:dbname=$cache_dbfile", "", "");
        unless (-f $cache_dbfile && -s _) {
            $cache_dbh->do("CREATE TABLE digest (inode INTEGER PRIMARY KEY, key TEXT, digest TEXT)");
            $cache_dbh->do("CREATE INDEX digest_inode ON digest (inode)");
        }
    };
    $cache_dbh= undef if $@;
}

if ($opts{e}) {
    print "Using '$opts{e}' as temporary directory.\n" unless $opts{q};
    $ds= DupMerge::DataStore->Factory(type => 'db', temp_dir => $opts{e});
}
else {
    print "Storing all databases in RAM.\n" unless $opts{q};
    $ds= DupMerge::DataStore->Factory(type => 'hash');
}
print "Skipping zero sized files.\n" if $opts{z} && !$opts{q};

# callback function for File::Find
sub processFiles {
    my $sFileName= $_;
    my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $bsize, $blocks)= lstat;
    # ignore all but regular files
    return unless $mode & S_IFREG;
    $sDev= $dev unless defined $sDev;
    unless ($dev == $sDev) {
        print "Directories span different devices\n";
        $opts{d} || die "Specify option -d to skip directories on other devices";
        return;
    }
    unless ($size || $opts{z}) {
        $stats{zerosized}++;
        return;
    }
    return if $opts{i} && $size < $opts{i};
    return if $opts{x} && $size >= $opts{x};
    $stats{total_files}++;
    # process every inode only once
    unless ($ds->inodeExists($inode)) { 
        $stats{total_inodes}++;
        # build key
        my $sKey= "";
        $sKey.= "_${mode}" unless $opts{p};
        $sKey.= "_${uid}_${gid}" unless $opts{o};
        $sKey.= "_${mtime}" unless $opts{t};
        $ds->addInodeSize($size, $sKey, $inode);
    }
    # store file names for each inode
    $ds->addInodeFile($inode, "${size}_${mode}_${uid}_${gid}_${mtime}", $sFileName);
}

# calculate digest from file
sub calcDigest {
    my $sFileName= shift;
    
    my $sDigest= undef;
    if (-r $sFileName) {
        eval {
            my $fh= undef;
            if (open $fh, '<', $sFileName) {
                $sDigest= Digest::SHA1->new()->addfile($fh)->b64digest;
                close $fh;
            }
            $stats{digest_calc}++;
        };
        return $sDigest unless $@;
        warn $@;
    }
    $stats{files_unreadable}++;
    return undef;
}

# get digest from cache db or calculate
sub getDigest {
    my $iInode= shift;
    my $ds= shift;
    
    my $sFileName= $ds->getFilesByInode($iInode)->[0];
    my $sDigest= undef;
    if ($cache_dbh) {
        eval {
            my $result= $cache_dbh->selectrow_hashref("SELECT * FROM digest WHERE inode = ?", undef, $iInode);
            if ($result) {
                if ($result->{"key"} eq $ds->getKeyByInode($iInode)) {
                    # use cached digest if inode is the same as last time
                    $sDigest= $result->{"digest"};
                    $stats{digest_cachehit}++;
                }
                else {
                    &removeFromCache($iInode);
                }
            }
        };
    }
    
    my $bCached= defined $sDigest;
    $sDigest= &calcDigest($sFileName) unless $bCached;
    return (
        digest => $sDigest,
        cached => $bCached,
    ) if wantarray;
    return $sDigest;
}

# write digest to cache db
sub setDigest {
    my $iInode= shift;
    my $ds= shift;
    my $sDigest= shift;
    
    return unless $cache_dbh;
    
    eval {
        $cache_dbh->do("INSERT INTO digest (inode, key, digest) VALUES (?, ?, ?)",
            undef, $iInode, $ds->getKeyByInode($iInode), $sDigest) unless $opts{n};
        $stats{digest_cacheadd}++;
    };
}

# remove digest from cache db
sub removeFromCache {
    my $iInode= shift;
    
    return unless $cache_dbh;
    eval {
        # delete old inode entry
        $cache_dbh->do("DELETE FROM digest WHERE inode = ?", undef, $iInode) unless $opts{n};
        $stats{digest_cacheremove}++;
    };
}

##############################################
# start actual working here
##############################################

print "Preparing information store..." unless $opts{q};

$ds->beginWork();

print "done\nCollecting file information..." unless $opts{q};

find({
    wanted => \&processFiles,
    no_chdir => 1,
}, @sDirectories);

print "done\nFinishing information store..." unless $opts{q};

$ds->endWork();

print "done\nSearching for duplicates...\n" unless $opts{q};

# traverse files starting with largest
for my $iSize (@{$ds->getDescSortedSizes()}) {
    print "\rProcessing file size $iSize...", " "x10 unless $opts{q};
    # handle files grouped by permissions etc. separately
    for my $sKey (@{$ds->getKeysBySize($iSize)}) {
        my $aInodes= $ds->getInodesBySizeKey($iSize, $sKey);
        unless (scalar @$aInodes > 1) {
            $stats{total_size}+= $iSize;
            next;
        }
        my %digests= ();
        # sort inodes by md5 hash
        for my $iInode (@$aInodes) {
            $stats{total_size}+= $iSize;
            my %digest= &getDigest($iInode, $ds);
            my $sDigest= $digest{digest};
            next unless defined $sDigest;
            $digests{$sDigest}= [] unless exists $digests{$sDigest};
            push @{$digests{$sDigest}}, {
                inode => $iInode,
                cached => $digest{cached},
            };
        }
        for my $sDigest (keys %digests) {
            # ignore digests with only one inode
            next unless scalar @{$digests{$sDigest}} > 1;

            # find inode with most hard links
            my $iMaxLinks= 0;
            my $iMaxInode= undef;
            my $sLinkFile= undef;
            for my $hInode (@{$digests{$sDigest}}) {
                my $iInode= $hInode->{inode};
                my $aFiles= $ds->getFilesByInode($iInode);
                if (scalar @$aFiles > $iMaxLinks) {
                    $iMaxLinks= scalar @$aFiles;
                    $iMaxInode= $iInode;
                    $sLinkFile= $aFiles->[0];
                }
            }
            # link all inodes with the most linked one
            for my $hInode (@{$digests{$sDigest}}) {
                my $iInode= $hInode->{inode};
                if ($iInode == $iMaxInode) {
                    &setDigest($iInode, $ds, $sDigest) unless $hInode->{cached};
                    next;
                }
                $stats{linked_size}+= -s $sLinkFile;
                for my $sFile (@{$ds->getFilesByInode($iInode)}) {
                    print "\rln -f '$sLinkFile' '$sFile'\n" if $opts{v};
                    unless ($opts{n}) {
                        if (unlink $sFile) {
                            link $sLinkFile, $sFile;
                            $stats{linked_files}++;
                        }
                        else {
                            $stats{linked_files_failed}++;
                        }
                    }
                    else {
                        $stats{linked_files}++;
                    }
                }
                &removeFromCache($iInode) if $hInode->{cached};
            }
        }
    }
}

$ds= $ds->destroy();

# print out some statistics
unless ($opts{q}) {
    print "\r...done", " "x20, "\n";
    my @sData= (
        {name => "total_files",        text => "Total files processed"},
        {name => "total_inodes",       text => "Total unique files"},
        {name => "zerosized",          text => "Zero sized Files"},
        {name => "total_size",         text => "Total file size in bytes"},
        {name => "linked_size",        text => "Freed space in bytes"},
        {name => "linked_files",       text => "Found duplicates"},
        {name => "linked_files_failed",text => "Failed duplicates"},
        {name => "digest_calc",        text => "Calculated digests"},
        {name => "files_unreadable",   text => "Unreadable files"},
        {name => "digest_cachehit",    text => "Digest cache hits"},
        {name => "digest_cacheadd",    text => "New digest cache entries"},
        {name => "digest_cacheremove", text => "Removed digest cache entries"},
    );
    print "statistics:\n";
    for my $data (@sData) {
        $stats{$data->{name}}+= 0;
        print "    ", substr("$data->{text}:" . "."x30, 0, 32);
        my $number= $stats{$data->{name}};
#         $number= sprintf '%12d', $number;
        while ($number=~ s/(\d)(\d\d\d(\,\d\d\d)*)$/$1,$2/) {};
        print " $number\n"; 
    }
}


sub HELP_MESSAGE {
    print "Usage:
$0 [<options> --] <path> [<path>]...
options: -h   Show this help message
         -d   Continue when directories span multiple devices (but ignore them)
              Program dies if paramter is not given and more than one device is used
         -p   Ignore permissions
         -o   Ignore ownership
         -t   Ignore file date/time
         -z   Don't ignore zero sized files
         -i <min size>
              Ignore files smaller than or equal <min size>
         -x <max size>
              Ignore files larger than <max size>
         -q   Don't print anything but errors/warnings
         -v   Verbose output
         -n   Dry run (don't change anything)
         -c <db file>
              Db for caching hash values
         -e <tempd dir>
              Temporary directory for data collection (use ram if not specified)
";
}

1;