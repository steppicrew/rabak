#!/usr/bin/perl

package RabakLib::DupMerge;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

use RabakLib::Trap;
use RabakLib::Log;
use RabakLib::InodeStore;
use RabakLib::InodeCache;
use RabakLib::Conf;

sub new {
    my $class= shift;
    my $hOptions= shift;

    my $self= {};
    $self->{OPTS}= $hOptions;
    $self->{INODE_CACHE}= RabakLib::InodeCache->new($hOptions);
    
    bless $self, $class;
}

sub _run {
    my $self= shift;
    
    my $oTrap= RabakLib::Trap->new();

    logger()->info("Searching for duplicates...");
    logger()->incIndent();
    
    # build array of relevant properties
    my $aQueryKey= [];
    push @$aQueryKey, "mode" unless $self->{OPTS}{ignore_perms};
    push @$aQueryKey, "owner" unless $self->{OPTS}{ignore_owner};
    push @$aQueryKey, "mtime" unless $self->{OPTS}{ignore_time};

    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    $oStore->beginCached();

    # traverse files starting with largest
    my $iSize= undef;
    my $aSizes= $oStore->getDescSortedSizes();
    while ($iSize= shift @$aSizes) {
        last if $oTrap->terminated();
        
        next unless $iSize || $self->{OPTS}{include_zero_sized};
        next if $self->{OPTS}{min_size} && $iSize < $self->{OPTS}{min_size};
        next if $self->{OPTS}{max_size} && $iSize > $self->{OPTS}{max_size};

        logger()->progress("Processing file size $iSize...");

        # handle files grouped by permissions etc. separately
        my $hKey= undef;
        my $aKeys= $oStore->getKeysBySize($iSize, $aQueryKey);
        while ($hKey= shift @$aKeys) {
	        last if $oTrap->terminated();

            my $aInodes= $oStore->getInodesBySizeKey($iSize, $hKey);
            unless (scalar @$aInodes > 1) {
                $self->{INODE_CACHE}{STATS}{total_size} += $iSize;
                next;
            }
            my %digests= ();

            # sort inodes by md5 hash
            for my $iInode (@$aInodes) {
		        last if $oTrap->terminated();

                $self->{INODE_CACHE}{STATS}{total_size} += $iSize;
                my %digest= $oCache->getDigest($iInode);
                my $sDigest= $digest{digest};
                next unless defined $sDigest;

                $digests{$sDigest}= [] unless exists $digests{$sDigest};
                push @{$digests{$sDigest}}, {
                    inode => $iInode,
                    cached => $digest{cached},
                };
            }
            for my $sDigest (keys %digests) {
		        last if $oTrap->terminated();

                # ignore digests with only one inode
                if (scalar @{$digests{$sDigest}} == 1) {
                    $oStore->setInodeDigest($digests{$sDigest}[0]{inode}, $sDigest) unless $digests{$sDigest}[0]{cached};
                    next;
                }
    
                # find inode with most hard links
                my $iMaxLinks= 0;
                my $iMaxInode= undef;
                my $sLinkFile= undef;
                my %FilesByInode= ();
                for my $hInode (@{$digests{$sDigest}}) {
			        last if $oTrap->terminated();

                    my $iInode= $hInode->{inode};
                    my $aFiles= $oStore->getFilesByInode($iInode);
                    unless (scalar @$aFiles) {

                        # Rausgenommen, falls nicht alle Verzeichnisse zum Vergleich angegeben werden
                        # $oStore->removeInode($iInode);
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
			        last if $oTrap->terminated();

                    my $iInode= $hInode->{inode};
                    next unless $FilesByInode{$iInode};

                    if ($iInode == $iMaxInode) {
                        $oStore->setInodeDigest($iInode, $sDigest) unless $hInode->{cached};
                        next;
                    }
                    $self->{INODE_CACHE}{STATS}{linked_size} += -s $sLinkFile;
                    my $bLinkError= 0;
                    for my $sFile (@{$FilesByInode{$iInode}}) {
				        last if $oTrap->terminated();

                        logger()->debug("ln -f '$sLinkFile' '$sFile'");
                        if ($self->{OPTS}{pretend}) {
                            $self->{INODE_CACHE}{STATS}{linked_files}++;
                            next;
                        }
                        
                        # find temporary file name
                        my $iTmpNum= "";
                        my $sTmpFile;
                        while (-e ($sTmpFile= "$sFile.tmp$iTmpNum")) { $iTmpNum++; }
                        
                        # try to make sure no data is lost
                        unless (link $sFile, $sTmpFile
                                    and unlink $sFile
                                    and link $sLinkFile, $sFile
                                    and unlink $sTmpFile
                        ) {
                            # if anything goes wrong, restore original file
                            if (-e $sTmpFile) {
                                unlink $sFile if -e $sFile;
                                rename $sTmpFile, $sFile;
                            }
                            $self->{INODE_CACHE}{STATS}{linked_files_failed}++;
                            logger()->warn("Failed to link file '$sLinkFile' -> '$sFile'");
                            $bLinkError= 1;
                            next;
                        }
                        
                        $self->{INODE_CACHE}{STATS}{linked_files}++;
                        $oStore->updateInodeFile($iMaxInode, $sFile);
                    }

                    # TODO: should inode be removed if not all directories are checked??
                    $oStore->removeInode($iInode) unless $self->{OPTS}{pretend} || $bLinkError;
                }
            }
        }
    }
    logger()->finish_progress("Processing files...done");
    logger()->decIndent();
    logger()->info("done");
    logger()->verbose("Finishing information store...");

    $oStore->endCached();
    $oStore->endWork();

    logger()->verbose("done");

    return !$oTrap->restore();
}

sub run {
    my $self= shift;
    
    return unless $self->{INODE_CACHE}->collect();

    $self->_run();

    $self->{INODE_CACHE}->printStats([
        {name => "total_size",         text => "Total file size in bytes"},
        {name => "linked_size",        text => "Freed space in bytes"},
        {name => "linked_files",       text => "Found duplicates"},
        {name => "linked_files_failed",text => "Failed duplicates"},
    ]);
}

1;