#!/usr/bin/perl

package Rabak::InodeCache;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

use Rabak::Log;
use Rabak::Trap;
use Rabak::InodeStore;

use File::Find;
use Data::Dumper;
use Fcntl ':mode';
use Digest::SHA1;
use Cwd;

sub new {
    my $class= shift;
    my $hOptions= shift;

    my $self= {};
    $self->{OPTS}= $hOptions;
    $self->{DS}= undef;
    $self->{STATS}= {};
    
    bless $self, $class;
    
    $self->_init();

    # print Dumper($self); die;
    return $self;
}

sub _init {
    my $self= shift;
    
    my %validDbEngines= (
        sqlite2 => "SQLite2",
        sqlite3 => "SQLite",
    );
    unless ($validDbEngines{$self->{OPTS}{db_backend} || ''}) {
        logger()->warn("Invalid database engine '$self->{OPTS}{db_backend}'.") if $self->{OPTS}{db_backend};
        $self->{OPTS}{db_backend}= "sqlite3";
    }

    # decide what InodeStore type will be used
    # currently the only supported type is multidb
    if (1) { 
        $self->{OPTS}{inodes_db}= "./inodes.db" unless $self->{OPTS}{inodes_db};
        $self->{OPTS}{db_postfix}= ".file_inode.db" unless $self->{OPTS}{db_postfix};
        logger()->debug("Using '$self->{OPTS}{inodes_db}' as inodes db.");
        logger()->debug("Using '$self->{OPTS}{db_postfix}' as postfix for multi db.");
        $self->{DS}= Rabak::InodeStore->Factory(
            type => 'multidb',
            inodes_db => $self->{OPTS}{inodes_db},
            temp_dir => $self->{OPTS}{temp_dir},
            db_postfix => $self->{OPTS}{db_postfix},
            db_backend => $self->{OPTS}{db_backend}
        );
    }
    
    logger()->info("Include skip zero sized files.") if $self->{OPTS}{include_zero_sized};
}

# adds given file to db
sub addFile {
    my $self= shift;
    my $sFileName= shift;
    my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $bsize, $blocks)= @_;
    
    ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $bsize, $blocks)= lstat $sFileName unless defined $dev;

    # ignore all but regular files
    return if ($mode & S_IFLNK) == S_IFLNK;
    return unless $mode & S_IFREG;

    $self->{dev}= $dev unless defined $self->{dev};
    unless ($dev == $self->{dev}) {
        logger()->warn("Directories span different devices. Ignoring file \"$sFileName\".");
        return;
    }
    $self->{STATS}{total_new_files}++;

    # process every inode only once (check if inode's hash matches this one)
    my @Hash= ($size, $mode, "${uid}_${gid}", $mtime);
    $self->{DS}->addInode($inode, @Hash) unless $self->{DS}->inodeExists($inode, @Hash);

    # store file names for each inode
    $self->{DS}->addInodeFile($inode, $sFileName, @Hash);
}

# callback function for File::Find
sub _processFiles {
    my $self= shift;
    my $oTrap= shift;

    return if $oTrap->terminated();
    
    $self->addFile($_);
}

# calculate digest from file
# DETECTED UNUSED: calcDigest
sub calcDigest {
    my $self= shift;
    my $sFileName= shift;
    
    my $sDigest= undef;
    if (-r $sFileName) {
        eval {
            my $fh= undef;
            if (open $fh, '<', $sFileName) {
                $sDigest= Digest::SHA1->new()->addfile($fh)->b64digest;
                close $fh;
            }
            $self->{STATS}{digest_calc}++;
        };
        return $sDigest unless $@;
        warn $@;
    }
    $self->{STATS}{files_unreadable}++;
    return undef;
}

# get digest from cache db or calculate
sub getDigest {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{DS}->getInodeDigest($iInode);
}

# write digest to cache db
sub setInodeDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    $self->{DS}->setInodeDigest($iInode, $sDigest);
    $self->{STATS}{digest_cacheadd}++;
}


sub prepareInformationStore {
    my $self= shift;
    my $sDir= shift;
    my $sDbFileName= shift;
    
    $self->{DS}->beginWork();
    $self->{DS}->registerAllInodes();
    $self->{DS}->newDirectory($sDir, $sDbFileName) if $sDir;
}

sub addDirectory {
    my $self= shift;
    my $sDir= shift;
    my $sDbFileName= shift;
    
    $self->{DS}->finishDirectory();
    my $result= $self->{DS}->newDirectory($sDir, $sDbFileName) if $sDir;
    $self->{DS}->finishDirectory() if !$result && $sDbFileName;
    return $result;
}

sub finishInformationStore {
    my $self= shift;

    $self->{DS}->finishDirectory();
    $self->{DS}->commitTransaction();
    $self->{DS}->endWork();
}

sub collect {
    my $self= shift;

    my $fTrapCB= undef;
    
    my $oTrap= Rabak::Trap->new(sub { $fTrapCB->() if $fTrapCB });

    logger()->verbose("Preparing information store...");
    $self->prepareInformationStore();
    logger()->verbose("done");
    logger()->info("Collecting file information...");

    my $aDirs= $self->{OPTS}{dirs};
    my %hDirsDone= ();
    for my $sRelDir (@$aDirs) {
    	last if $oTrap->terminated();

        my $sDir= Cwd::abs_path($sRelDir);
        unless (defined $sDir && -d $sDir) {
            logger()->warn("'$sRelDir' is not a directory. Skipping.");
            next;
        }
        if (-l $sDir) {
            logger()->warn("'$sRelDir' is a symlink. Skipping.");
            next;
        }
        if (exists $hDirsDone{$sDir}) {
            logger()->warn("Directory '$sDir' has already been scanned. Skipping.");
            next;
        }
        $hDirsDone{$sDir}= undef;
        logger()->incIndent();
        my $sInfo= "Processing directory '$sDir'";
        if ($self->addDirectory($sDir)) {
            logger()->info("$sInfo...");
            $fTrapCB= sub{$self->{DS}->invalidate()};
            find({
                wanted => sub { $self->_processFiles($oTrap); },
                no_chdir => 1,
            }, $sDir);
            $sInfo= "done";
        }
        else {
            $sInfo.= " (cached)";
        }
        $self->{DS}->finishDirectory();
        $fTrapCB= undef;
        logger()->info($sInfo);
        logger()->decIndent();
    }
    $self->{STATS}{total_inodes}= $self->{DS}->getInodeCount();
    logger()->info("done");
    logger()->verbose("Finishing information store...");
    $self->finishInformationStore();
    logger()->verbose("done");

    return !$oTrap->restore();
}

# print out some statistics
sub printStats {
    my $self= shift;
    my $aData= shift || ();

	unshift @$aData, (
        {name => "total_new_files",    text => "Total new files processed"},
        {name => "total_cached_files", text => "Total cached files processed"},
        {name => "total_inodes",       text => "Total unique files"},
        {name => "zerosized",          text => "Zero sized Files"},
        {name => "digest_calc",        text => "Calculated digests"},
        {name => "files_unreadable",   text => "Unreadable files"},
        {name => "digest_cachehit",    text => "Digest cache hits"},
        {name => "digest_cacheadd",    text => "New digest cache entries"},
	);
	    
    logger()->info("Statistics:");
    for my $data (@$aData) {
        $self->{STATS}{$data->{name}} += 0;
        my $number= $self->{STATS}{$data->{name}};
        while ($number=~ s/(\d)(\d\d\d(\,\d\d\d)*)$/$1,$2/) {};
        logger()->info("    " . substr("$data->{text}:" . "." x 30, 0, 32) . $number);
    }
}

1;
