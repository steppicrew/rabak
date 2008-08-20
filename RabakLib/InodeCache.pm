#!/usr/bin/perl

package RabakLib::InodeCache;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

use RabakLib::Log;
use RabakLib::Trap;
use RabakLib::InodeStore;

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

 	# print Dumper($self); die;
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
        $self->{OPTS}{db_inodes_dir}= "." unless $self->{OPTS}{db_inodes_dir};
        $self->{OPTS}{db_postfix}= ".file_inode.db" unless $self->{OPTS}{db_postfix};
        logger()->debug("Using '$self->{OPTS}{db_inodes_dir}' as inode's db directory.");
        logger()->debug("Using '$self->{OPTS}{db_postfix}' as postfix for multi db.");
        $self->{DS}= RabakLib::InodeStore->Factory(
            type => 'multidb',
            db_inodes_dir => $self->{OPTS}{db_inodes_dir},
            temp_dir => $self->{OPTS}{temp_dir},
            db_postfix => $self->{OPTS}{db_postfix},
            db_backend => $self->{OPTS}{db_backend}
        );
    }
    
    logger()->info("Include skip zero sized files.") if $self->{OPTS}{include_zero_sized};
}

# callback function for File::Find
sub _processFiles {
    my $self= shift;
    my $oTrap= shift;

    return if $oTrap->terminated();
    
    my $sFileName= $_;
    my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $bsize, $blocks)= lstat;

    # ignore all but regular files
    return if ($mode & S_IFLNK) == S_IFLNK;
    return unless $mode & S_IFREG;

    $self->{dev}= $dev unless defined $self->{dev};
    unless ($dev == $self->{dev}) {
        logger()->warn("Directories span different devices");
        return;
    }
    $self->{STATS}{total_new_files}++;

    # process every inode only once
    $self->{DS}->addInode($inode, $size, $mode, "${uid}_${gid}", $mtime) unless $self->{DS}->inodeExists($inode);

    # store file names for each inode
    $self->{DS}->addInodeFile($inode, $sFileName);
}

# calculate digest from file
sub _calcDigest {
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
    
    my $sDigest= $self->{DS}->getInodeDigest($iInode);
    
    my $bCached= defined $sDigest;
    if ($bCached) {
        $self->{STATS}{digest_cachehit}++;
    }
    else {
        my $sFileName= $self->{DS}->getOneFileByInode($iInode);
        return () unless $sFileName;
        
        logger()->verbose("Calculating digest for '$sFileName'");
        $sDigest= $self->_calcDigest($sFileName);
    }

    return (
        digest => $sDigest,
        cached => $bCached,
    );
}

# write digest to cache db
sub setInodeDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    $self->{DS}->setInodeDigest($iInode, $sDigest);
    $self->{STATS}{digest_cacheadd}++;
}


sub collect {
    my $self= shift;

	$self->_init();

    my $fTrapCB= undef;
    
    my $oTrap= RabakLib::Trap->new(sub {$fTrapCB->() if $fTrapCB});

    logger()->info("Preparing information store...");
    $self->{DS}->beginWork();
    $self->{DS}->registerInodes($self->{DS}->getInodes());
    logger()->info("done");
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
        logger()->info("Processing directory '$sDir'...");
        if ($self->{DS}->newDirectory($sDir)) {
            $fTrapCB= sub{$self->{DS}->invalidate()};
            find({
                wanted => sub { $self->_processFiles($oTrap); },
                no_chdir => 1,
            }, $sDir);
        }
        else {
##            $self->{STATS}{total_cached_files}+= $self->{DS}->getCurrentFileCount();
            logger()->info("(cached)");
        }
        $self->{DS}->finishDirectory();
        $fTrapCB= undef;
        logger()->info("done");
        logger()->decIndent();
    }
    $self->{STATS}{total_inodes}= $self->{DS}->getInodeCount();
    logger()->info("done", "Finishing information store...");
    $self->{DS}->commitTransaction();
    logger()->info("done");

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