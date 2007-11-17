#!/usr/bin/perl

package DupMerge::DupMerge;

#TODO: change key for persistant inode_size db


use strict;
use File::Find;
use Data::Dumper;
use Fcntl ':mode';
use Digest::SHA1;
use Cwd;

use DupMerge::DataStore;

sub new {
    my $class= shift;
    my $aDirectories= shift;
    my $hOptions= shift;
    
    my $self= {
        dirs => $aDirectories,
        opts => $hOptions,
        
        device => undef,
        ds => undef,
        stats => {},
    };
    
    bless $self, $class;
}

sub init {
    my $self= shift;
    
    my %validDbEngines= (
        sqlite2 => "SQLite2",
        sqlite3 => "SQLite",
    );
    unless ($validDbEngines{$self->{opts}{db_engine} || ''}) {
        $self->warnMsg("Invalid database engine '$self->{opts}{db_engine}'.") if $self->{opts}{db_engine};
        $self->{opts}{db_engine}= "sqlite3";
    }
    
    # decide what DataStore type will be used
    if ($self->{opts}{multi_db_prefix}) {
        $self->{opts}{work_dir}= "/tmp" unless $self->{opts}{work_dir};
        $self->infoMsg("Using '$self->{opts}{work_dir}' as working directory.");
        $self->infoMsg("Using '$self->{opts}{multi_db_prefix}' as prefix for multi db.");
        $self->{ds}= DupMerge::DataStore->Factory(
            type => 'multidb',
            work_dir => $self->{opts}{work_dir},
            db_prefix => $self->{opts}{multi_db_prefix},
            db_engine => $self->{opts}{db_engine}
        );
    }
    elsif ($self->{opts}{work_dir}) {
        $self->infoMsg("Using '$self->{opts}{work_dir}' as working directory.");
        $self->{ds}= DupMerge::DataStore->Factory(
            type => 'db',
            work_dir => $self->{opts}{work_dir},
            db_engine => $self->{opts}{db_engine}
        );
    }
    else {
        $self->infoMsg("Storing all databases in RAM.");
        $self->{ds}= DupMerge::DataStore->Factory(type => 'hash');
    }
    
    $self->infoMsg("Skipping zero sized files.") if $self->{opts}{skip_zero};

}

sub setOptions {
    my $self= shift;
    my $hOptions= shift;
    $self->{opts}= $hOptions || {};
}

sub infoMsg {
    my $self= shift;
    return $self->{opts}{cb_info}(@_) if $self->{opts}{cb_info};
    $self->infoMsgS(@_, '');
}

# do not append \n after last line
sub infoMsgS {
    my $self= shift;
    return $self->{opts}{cb_infoS}(@_) if $self->{opts}{cb_infoS};
    print join "\n", @_ unless $self->{opts}{quiet};
    STDOUT->flush();
}

sub verbMsg {
    my $self= shift;
    return $self->{opts}{cb_verbose}(@_) if $self->{opts}{cb_verbose};
    $self->infoMsg(@_) if $self->{opts}{verbose};
}

sub warnMsg {
    my $self= shift;
    return $self->{opts}{cb_warn}(@_) if $self->{opts}{cb_warn};
    warn @_;
}

# callback function for File::Find
sub processFiles {
    my $self= shift;

    die "\$thisObject is not set - Internal error!" unless $self;

    my $sFileName= $_;
    my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $bsize, $blocks)= lstat;
    # ignore all but regular files
    return unless $mode & S_IFREG;
    $self->{dev}= $dev unless defined $self->{dev};
    unless ($dev == $self->{dev}) {
        $self->warnMsg("Directories span different devices");
        die "Specify option -d to skip directories on other devices" unless $self->{opts}{ignore_devspans};
        return;
    }
    unless ($size || $self->{opts}{skip_zero}) {
        $self->{stats}{zerosized}++;
        return;
    }
    return if $self->{opts}{min_size} && $size <  $self->{opts}{min_size};
    return if $self->{opts}{max_size} && $size >= $self->{opts}{max_size};
    $self->{stats}{total_new_files}++;
    # process every inode only once
    $self->{ds}->addInode($inode, $size, $mode, "${uid}_${gid}", $mtime) unless $self->{ds}->inodeExists($inode);
    # store file names for each inode
    $self->{ds}->addInodeFile($inode, $sFileName);
}

# calculate digest from file
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
            $self->{stats}{digest_calc}++;
        };
        return $sDigest unless $@;
        warn $@;
    }
    $self->{stats}{files_unreadable}++;
    return undef;
}

# get digest from cache db or calculate
sub getDigest {
    my $self= shift;
    my $iInode= shift;
    
    my $aFileNames= $self->{ds}->getFilesByInode($iInode);
    return {} unless scalar @$aFileNames;
    my $sFileName= $aFileNames->[0];
    my $sDigest= $self->{ds}->getDigestByInode($iInode);
    
    my $bCached= defined $sDigest;
    if ($bCached) {
        $self->{stats}{digest_cachehit}++;
    }
    else {
        $sDigest= $self->calcDigest($sFileName);
    }

    return (
        digest => $sDigest,
        cached => $bCached,
    ) if wantarray;

    return $sDigest;
}

# write digest to cache db
sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    $self->{ds}->setInodesDigest($iInode, $sDigest);
    $self->{stats}{digest_cacheadd}++;
}

sub terminate {
    my $self= shift;
    $self->{ds}->terminate();
    exit 1;
}

sub pass1 {
    my $self= shift;
    my $aDirs= shift;

    # trap signals for cleaning up
    my %oldSig= ();
    my @signals= ("INT", "TERM", "QUIT", "KILL");
    my $sigHandler= sub { $self->terminate(); };
    for my $sSig (@signals) {
        $oldSig{$sSig}= $SIG{$sSig};
        $SIG{$sSig}= $sigHandler;
    }

    $self->infoMsgS("Preparing information store...");
    $self->{ds}->beginWork();
    $self->{ds}->registerInodes($self->{ds}->getInodes());
    $self->{ds}->beginInsert();
    $self->infoMsg("done", "Collecting file information...");

    my %hDirsDone= ();
    for my $sDir (@$aDirs) {
        $sDir= Cwd::abs_path($sDir);
        unless (-d $sDir) {
            $self->warnMsg("'$sDir' is not a directory. Skipping.");
            next;
        }
        if (exists $hDirsDone{$sDir}) {
            $self->warnMsg("Directory '$sDir' has already been scanned. Skipping.");
            next;
        }
        $hDirsDone{$sDir}= undef;
        $self->infoMsgS("\tProcessing directory '$sDir'...");
        if ($self->{ds}->newDirectory($sDir)) {
            find({
                wanted => sub {$self->processFiles();},
                no_chdir => 1,
            }, $sDir);
        }
        else {
            $self->{stats}{total_cached_files}+= $self->{ds}->getCurrentFileCount();
        }
        $self->{ds}->finishDirectory();
        $self->infoMsg("done");
    }
    $self->{stats}{total_inodes}= $self->{ds}->getInodeCount();
    $self->infoMsgS("done", "Finishing information store...");
    $self->{ds}->endInsert();
    $self->infoMsg("done");

    # restore signal handler
    for my $sSig (@signals) {
        $SIG{$sSig}= $oldSig{$sSig};
    }
}

sub pass2 {
    my $self= shift;
    
    $self->infoMsg("Searching for duplicates...");
    
    # build array of relevant properties
    my $aQueryKey= [];
    push @$aQueryKey, "mode" unless $self->{opts}{ignore_perms};
    push @$aQueryKey, "owner" unless $self->{opts}{ignore_owner};
    push @$aQueryKey, "mtime" unless $self->{opts}{ignore_time};

    # traverse files starting with largest
    for my $iSize (@{$self->{ds}->getDescSortedSizes()}) {
        $self->infoMsgS("\rProcessing file size $iSize..." . " "x10);
    #   handle files grouped by permissions etc. separately
        for my $hKey (@{$self->{ds}->getKeysBySize($iSize, $aQueryKey)}) {
            my $aInodes= $self->{ds}->getInodesBySizeKey($iSize, $hKey);
            unless (scalar @$aInodes > 1) {
                $self->{stats}{total_size}+= $iSize;
                next;
            }
            my %digests= ();
        #   sort inodes by md5 hash
            for my $iInode (@$aInodes) {
                $self->{stats}{total_size}+= $iSize;
                my %digest= $self->getDigest($iInode);
                my $sDigest= $digest{digest};
                next unless defined $sDigest;
                $digests{$sDigest}= [] unless exists $digests{$sDigest};
                push @{$digests{$sDigest}}, {
                    inode => $iInode,
                    cached => $digest{cached},
                };
            }
            for my $sDigest (keys %digests) {
            #   ignore digests with only one inode
                next unless scalar @{$digests{$sDigest}} > 1;
    
            #   find inode with most hard links
                my $iMaxLinks= 0;
                my $iMaxInode= undef;
                my $sLinkFile= undef;
                my %FilesByInode= ();
                for my $hInode (@{$digests{$sDigest}}) {
                    my $iInode= $hInode->{inode};
                    my $aFiles= $self->{ds}->getFilesByInode($iInode);
                    unless (scalar @$aFiles) {
                        $self->{ds}->removeInode($iInode);
                        next;
                    }
                    # remember file list for next loop
                    $FilesByInode{$iInode}= $aFiles;
                    if (scalar @$aFiles > $iMaxLinks) {
                        $iMaxLinks= scalar @$aFiles;
                        $iMaxInode= $iInode;
                        $sLinkFile= $aFiles->[0];
                    }
                }
            #   link all inodes with the most linked one
                for my $hInode (@{$digests{$sDigest}}) {
                    my $iInode= $hInode->{inode};
                    next unless $FilesByInode{$iInode};
                    if ($iInode == $iMaxInode) {
                        $self->setInodesDigest($iInode, $sDigest) unless $hInode->{cached};
                        next;
                    }
                    $self->{stats}{linked_size}+= -s $sLinkFile;
                    for my $sFile (@{$FilesByInode{$iInode}}) {
                        $self->verbMsg("\rln -f '$sLinkFile' '$sFile'");
                        unless ($self->{opts}{dryrun}) {
                            if (unlink $sFile) {
                                link $sLinkFile, $sFile;
                                $self->{stats}{linked_files}++;
                                $self->{ds}->updateInodeFile($iMaxInode, $sFile);
                            }
                            else {
                                $self->{stats}{linked_files_failed}++;
                            }
                        }
                        else {
                            $self->{stats}{linked_files}++;
                        }
                    }
                    $self->{ds}->removeInode($iInode) unless $self->{opts}{dryrun};
                }
            }
        }
    }
    $self->infoMsg("\r...done" . " "x20);
}

sub printStat {
    my $self= shift;
    
#   print out some statistics
    my @sData= (
        {name => "total_new_files",    text => "Total new files processed"},
        {name => "total_cached_files", text => "Total cached files processed"},
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
    );
    $self->infoMsg("Statistics:");
    for my $data (@sData) {
        $self->{stats}{$data->{name}}+= 0;
        my $number= $self->{stats}{$data->{name}};
        while ($number=~ s/(\d)(\d\d\d(\,\d\d\d)*)$/$1,$2/) {};
        $self->infoMsg("    " . substr("$data->{text}:" . "."x30, 0, 32) . $number);
    }

    $self->{ds}= $self->{ds}->endWork();
}

sub run {
    my $self= shift;
    my $aDirs= shift || $self->{dirs};
    my $hOptions= shift;
    
    $self->setOptions($hOptions) if $hOptions;
    $self->init();

    $self->pass1($aDirs);
    $self->pass2();
    $self->printStat();
}

1;