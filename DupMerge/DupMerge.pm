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
        
        old_signals=> undef,
        _terminate=> undef,
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
    # currently the only supported type is multidb
    if (1) { 
        $self->{opts}{base_dir}= "." unless $self->{opts}{base_dir};
        $self->{opts}{multi_db_postfix}= ".file_inode.db" unless $self->{opts}{multi_db_postfix};
        $self->infoMsg("Using '$self->{opts}{base_dir}' as working directory.");
        $self->infoMsg("Using '$self->{opts}{multi_db_postfix}' as postfix for multi db.");
        $self->{ds}= DupMerge::DataStore->Factory(
            type => 'multidb',
            base_dir => $self->{opts}{base_dir},
            temp_dir => $self->{opts}{temp_dir},
            db_postfix => $self->{opts}{multi_db_postfix},
            db_engine => $self->{opts}{db_engine}
        );
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

    return if  $self->{_terminate};
    
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
    
    my $sDigest= $self->{ds}->getDigestByInode($iInode);
    
    my $bCached= defined $sDigest;
    if ($bCached) {
        $self->{stats}{digest_cachehit}++;
    }
    else {
        my $sFileName= $self->{ds}->getOneFileByInode($iInode);
        return {} unless $sFileName;
        
        $self->verbMsg("Calculating digest for '$sFileName'");
        $sDigest= $self->calcDigest($sFileName);
    }

    return (
        digest => $sDigest,
        cached => $bCached,
    );
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
    
    $self->warnMsg("\n**** Caught interrupt. Finishing information store...",
        "Press [Ctrl-C] again to cancel (may result in db information loss).");
    $self->restoreTraps();
    $self->{_terminate}= 1;
}

sub setTraps {
    my $self= shift;
    return if $self->{old_signals};
    # trap signals for cleaning up
    $self->{old_signals}= {};
    my @signals= ("INT", "TERM", "QUIT", "KILL");
    my $sigHandler= sub { $self->terminate(); };
    for my $sSig (@signals) {
        $self->{old_signals}{$sSig}= $SIG{$sSig};
        $SIG{$sSig}= $sigHandler;
    }
}

sub restoreTraps {
    my $self= shift;
    return unless $self->{old_signals};
    # restore signal handler
    for my $sSig (keys %{$self->{old_signals}}) {
        $SIG{$sSig}= $self->{old_signals}{$sSig};
    }
    $self->{old_signals}= undef;
}

sub pass1 {
    my $self= shift;
    my $aDirs= shift;
    
    $self->setTraps();

    $self->infoMsgS("Preparing information store...");
    $self->{ds}->beginWork();
    $self->{ds}->registerInodes($self->{ds}->getInodes());
    $self->infoMsg("done", "Collecting file information...");

    my %hDirsDone= ();
    for my $sDir (@$aDirs) {
        last if  $self->{_terminate};
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
##            $self->{stats}{total_cached_files}+= $self->{ds}->getCurrentFileCount();
            $self->infoMsgS("(cached) ");
        }
        $self->{ds}->finishDirectory();
        $self->infoMsg("done");
    }
    $self->{stats}{total_inodes}= $self->{ds}->getInodeCount();
    $self->infoMsgS("done", "Finishing information store...");
    $self->{ds}->commitTransaction();
    $self->infoMsg("done");

    $self->restoreTraps();
}

sub pass2 {
    my $self= shift;
    
    $self->setTraps();

    $self->infoMsg("Searching for duplicates...");
    
    # build array of relevant properties
    my $aQueryKey= [];
    push @$aQueryKey, "mode" unless $self->{opts}{ignore_perms};
    push @$aQueryKey, "owner" unless $self->{opts}{ignore_owner};
    push @$aQueryKey, "mtime" unless $self->{opts}{ignore_time};

    $self->{ds}->beginCached();

    # traverse files starting with largest
    my $iSize= undef;
    my $aSizes= $self->{ds}->getDescSortedSizes();
    while ($iSize= shift @$aSizes) {
        last if  $self->{_terminate};
        next unless $iSize || $self->{opts}{skip_zero};
        next if $self->{opts}{min_size} && $iSize <  $self->{opts}{min_size};
        next if $self->{opts}{max_size} && $iSize >= $self->{opts}{max_size};

        $self->infoMsgS("\rProcessing file size $iSize..." . " "x10);

        # handle files grouped by permissions etc. separately
        my $hKey= undef;
        my $aKeys= $self->{ds}->getKeysBySize($iSize, $aQueryKey);
        while ($hKey= shift @$aKeys) {
            last if  $self->{_terminate};

            my $aInodes= $self->{ds}->getInodesBySizeKey($iSize, $hKey);
            unless (scalar @$aInodes > 1) {
                $self->{stats}{total_size}+= $iSize;
                next;
            }
            my %digests= ();

            # sort inodes by md5 hash
            for my $iInode (@$aInodes) {
                last if  $self->{_terminate};

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
                last if  $self->{_terminate};

                # ignore digests with only one inode
                if (scalar @{$digests{$sDigest}} == 1) {
                    $self->setInodesDigest($digests{$sDigest}[0]{inode}, $sDigest) unless $digests{$sDigest}[0]{cached};
                    next;
                }
    
                # find inode with most hard links
                my $iMaxLinks= 0;
                my $iMaxInode= undef;
                my $sLinkFile= undef;
                my %FilesByInode= ();
                for my $hInode (@{$digests{$sDigest}}) {
                    last if  $self->{_terminate};

                    my $iInode= $hInode->{inode};
                    my $aFiles= $self->{ds}->getFilesByInode($iInode);
                    unless (scalar @$aFiles) {

                        # Rausgenommen, falls nicht alle Verzeichnisse zum Vergleich angegeben werden
                        # $self->{ds}->removeInode($iInode);
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

                # link all inodes with the most linked one
                for my $hInode (@{$digests{$sDigest}}) {
                    last if  $self->{_terminate};

                    my $iInode= $hInode->{inode};
                    next unless $FilesByInode{$iInode};

                    if ($iInode == $iMaxInode) {
                        $self->setInodesDigest($iInode, $sDigest) unless $hInode->{cached};
                        next;
                    }
                    $self->{stats}{linked_size}+= -s $sLinkFile;
                    my $bLinkError= 0;
                    for my $sFile (@{$FilesByInode{$iInode}}) {
                        last if  $self->{_terminate};

                        $self->verbMsg("\rln -f '$sLinkFile' '$sFile'");
                        if ($self->{opts}{dryrun}) {
                            $self->{stats}{linked_files}++;
                            next;
                        }
                        
                        # find temporary file name
                        my $iTmpNum= "";
                        my $sTmpFile;
                        while (-e ($sTmpFile= "$sFile.tmp$iTmpNum")) {$iTmpNum++;}
                        
                        # try to make sure no data is lost
                        unless (link $sFile, $sTmpFile
                                    and unlink $sFile
                                    and link $sLinkFile, $sFile
                                    and unlink $sTmpFile) {
                            # if anything goes wrong, restore original file
                            if (-e $sTmpFile) {
                                unlink $sFile if -e $sFile;
                                rename $sTmpFile, $sFile;
                            }
                            $self->{stats}{linked_files_failed}++;
                            $self->warnMsg("\rFailed to link file '$sLinkFile' -> '$sFile'");
                            $bLinkError= 1;
                            next;
                        }
                        
                        $self->{stats}{linked_files}++;
                        $self->{ds}->updateInodeFile($iMaxInode, $sFile);
                    }
                    # TODO: should inode be removed if not all directories are checked??
                    $self->{ds}->removeInode($iInode) unless $self->{opts}{dryrun} || $bLinkError;
                }
            }
        }
    }
    $self->infoMsgS("\r...done" . " "x20, "Finishing information store...");

    $self->{ds}->endCached();
    $self->{ds}->endWork();

    $self->infoMsg("done");

    $self->restoreTraps();
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
}

sub run {
    my $self= shift;
    my $aDirs= shift || $self->{dirs};
    my $hOptions= shift;
    
    $self->setOptions($hOptions) if $hOptions;
    $self->init();

    $self->pass1($aDirs) unless $self->{_terminate};
    $self->pass2() unless $self->{_terminate};
    $self->printStat();
}

1;