#!/usr/bin/perl

package DupMerge::DupMerge;

use strict;
use Getopt::Std;
use File::Find;
use Data::Dumper;
use Fcntl ':mode';
use Digest::SHA1;
use DBI;

use DupMerge::DataStore;

sub new {
    my $class= shift;
    my $aDirectories= shift;
    my $hOptions= shift;
    
    my $self= {
        dirs => $aDirectories,
        opts => $hOptions,
        
        device => undef,
        cache_dbh => undef,
        ds => undef,
        stats => {},
    };
    
    bless $self, $class;
}

sub setOptions {
    my $self= shift;
    my $hOptions= shift;
    $self->{opts}= $hOptions || {};
}

sub init {
    my $self= shift;
    
    if ($self->{opts}{digest_db_file}) {
        my $cache_dbfile= $self->{opts}{digest_db_file};
        $self->infoMsg("Using file '$cache_dbfile' for digest caching.");
        eval {
            $self->{cache_dbh} = DBI->connect("dbi:SQLite2:dbname=$cache_dbfile", "", "");
            if ($self->{cache_dbh}) {
                unless (-f $cache_dbfile && -s _) {
                    $self->{cache_dbh}->do("CREATE TABLE digest (inode INTEGER PRIMARY KEY, key TEXT, digest TEXT)");
                    $self->{cache_dbh}->do("CREATE INDEX digest_inode ON digest (inode)");
                }
            }
        };
        if ($@) {
            warn $@;
            $self->{cache_dbh}= undef;
        }
    }
    if ($self->{opts}{temp_dir}) {
        $self->infoMsg("Using '$self->{opts}{temp_dir}' as temporary directory.");
        $self->{ds}= DupMerge::DataStore->Factory(type => 'db', temp_dir => $self->{opts}{temp_dir});
    }
    else {
        $self->infoMsg("Storing all databases in RAM.");
        $self->{ds}= DupMerge::DataStore->Factory(type => 'hash');
    }
    $self->infoMsg("Skipping zero sized files.") if $self->{opts}{skip_zero};

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
    $self->{stats}{total_files}++;
    # process every inode only once
    unless ($self->{ds}->inodeExists($inode)) { 
        $self->{stats}{total_inodes}++;
        # build key
        my $sKey= "";
        $sKey.= "_${mode}" unless $self->{opts}{ignore_perms};
        $sKey.= "_${uid}_${gid}" unless $self->{opts}{ignore_owner};
        $sKey.= "_${mtime}" unless $self->{opts}{ignore_time};
        $self->{ds}->addInodeSize($size, $sKey, $inode);
    }
    # store file names for each inode
    $self->{ds}->addInodeFile($inode, "${size}_${mode}_${uid}_${gid}_${mtime}", $sFileName);
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
    
    my $sFileName= $self->{ds}->getFilesByInode($iInode)->[0];
    my $sDigest= undef;
    if ($self->{cache_dbh}) {
        eval {
            my $result= $self->{cache_dbh}->selectrow_hashref("SELECT * FROM digest WHERE inode = ?", undef, $iInode);
            if ($result) {
                if ($result->{"key"} eq $self->{ds}->getKeyByInode($iInode)) {
                    # use cached digest if inode is the same as last time
                    $sDigest= $result->{"digest"};
                    $self->{stats}{digest_cachehit}++;
                }
                else {
                    $self->removeFromCache($iInode);
                }
            }
        };
    }
    
    my $bCached= defined $sDigest;
    $sDigest= $self->calcDigest($sFileName) unless $bCached;
    return (
        digest => $sDigest,
        cached => $bCached,
    ) if wantarray;
    return $sDigest;
}

# write digest to cache db
sub setDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return unless $self->{cache_dbh};
    
    eval {
        $self->{cache_dbh}->do("INSERT INTO digest (inode, key, digest) VALUES (?, ?, ?)",
            undef, $iInode, $self->{ds}->getKeyByInode($iInode), $sDigest) unless $self->{opts}{dryrun};
        $self->{stats}{digest_cacheadd}++;
    };
}

# remove digest from cache db
sub removeFromCache {
    my $self= shift;
    my $iInode= shift;
    
    return unless $self->{cache_dbh};
    eval {
        # delete old inode entry
        $self->{cache_dbh}->do("DELETE FROM digest WHERE inode = ?", undef, $iInode) unless $self->{opts}{dryrun};
        $self->{stats}{digest_cacheremove}++;
    };
}

sub run {
    my $self= shift;
    my $aDirs= shift || $self->{dirs};
    my $hOptions= shift;
    
    $self->setOptions($hOptions) if $hOptions;
    $self->init();

    $self->infoMsgS("Preparing information store...");
    $self->{ds}->beginWork();
    $self->infoMsgS("done", "Collecting file information...");

    find({
        wanted => sub {$self->processFiles();},
        no_chdir => 1,
    }, @$aDirs);

    $self->infoMsgS("done", "Finishing information store...");
    $self->{ds}->endWork();
    $self->infoMsg("done", "Searching for duplicates...");

    # traverse files starting with largest
    for my $iSize (@{$self->{ds}->getDescSortedSizes()}) {
        $self->infoMsgS("\rProcessing file size $iSize..." . " "x10);
    #   handle files grouped by permissions etc. separately
        for my $sKey (@{$self->{ds}->getKeysBySize($iSize)}) {
            my $aInodes= $self->{ds}->getInodesBySizeKey($iSize, $sKey);
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
                for my $hInode (@{$digests{$sDigest}}) {
                    my $iInode= $hInode->{inode};
                    my $aFiles= $self->{ds}->getFilesByInode($iInode);
                    if (scalar @$aFiles > $iMaxLinks) {
                        $iMaxLinks= scalar @$aFiles;
                        $iMaxInode= $iInode;
                        $sLinkFile= $aFiles->[0];
                    }
                }
            #   link all inodes with the most linked one
                for my $hInode (@{$digests{$sDigest}}) {
                    my $iInode= $hInode->{inode};
                    if ($iInode == $iMaxInode) {
                        $self->setDigest($iInode, $sDigest) unless $hInode->{cached};
                        next;
                    }
                    $self->{stats}{linked_size}+= -s $sLinkFile;
                    for my $sFile (@{$self->{ds}->getFilesByInode($iInode)}) {
                        $self->verbMsg("\rln -f '$sLinkFile' '$sFile'");
                        unless ($self->{opts}{dryrun}) {
                            if (unlink $sFile) {
                                link $sLinkFile, $sFile;
                                $self->{stats}{linked_files}++;
                            }
                            else {
                                $self->{stats}{linked_files_failed}++;
                            }
                        }
                        else {
                            $self->{stats}{linked_files}++;
                        }
                    }
                    $self->removeFromCache($iInode) if $hInode->{cached};
                }
            }
        }
    }

    $self->{ds}= $self->{ds}->destroy();
    
#   print out some statistics
    $self->infoMsg("\r...done" . " "x20);
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
    $self->infoMsg("Statistics:");
    for my $data (@sData) {
        $self->{stats}{$data->{name}}+= 0;
        my $number= $self->{stats}{$data->{name}};
        while ($number=~ s/(\d)(\d\d\d(\,\d\d\d)*)$/$1,$2/) {};
        $self->infoMsg("    " . substr("$data->{text}:" . "."x30, 0, 32) . $number);
    }
}

1;