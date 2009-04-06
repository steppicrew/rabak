#!/usr/bin/perl

package Rabak::DupMerge;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

use Rabak::Trap;
use Rabak::Log;
use Rabak::InodeCache;

sub new {
    my $class= shift;
    my $hOptions= shift;

    my $self= {};
    $self->{OPTS}= $hOptions;
    if ($hOptions->{INODE_CACHE}) {
        $self->{INODE_CACHE}= $hOptions->{INODE_CACHE};
    }
    else {
        $self->{INODE_CACHE}= Rabak::InodeCache->new($hOptions);
    }
    
    bless $self, $class;
}

# seraches for duplicates and calls $fLinkFiles with hash table of 
sub dupmerge {
    my $self= shift;
    my $fSimilarInodes= shift || sub {$self->_processSimilarInodes(@_)};
    
    my $oTrap= Rabak::Trap->new();

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
            $fSimilarInodes->($aInodes);
        }
    }
    logger()->finish_progress("Processing files...done");
    logger()->decIndent();
    logger()->info("done");

    return !$oTrap->restore();
}

sub _processSimilarInodes {
    my $self= shift;
    my $aInodes= shift;
    my $fLinkFiles= shift || sub {$self->_linkFiles(@_)};
    
    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    return unless scalar @$aInodes > 1;
    
    # build hash (digest => [inode, inode...])
    my %digests= ();
    for my $iInode (@$aInodes) {
#        last if $oTrap->terminated();

        my $sDigest= $oCache->getDigest($iInode);
        unless (defined $sDigest) {
            my $sFileName= $oStore->getOneFileByInode($iInode);
            next unless defined $sFileName;
            logger->("Calculating digest for \"$sFileName\".");
            $sDigest= $oCache->calcDigest($sFileName);
            $oStore->setInodeDigest($iInode, $sDigest);
        }

        $digests{$sDigest}= [] unless exists $digests{$sDigest};
        push @{$digests{$sDigest}}, $iInode;
    }

    # process inodes with the same digest
    for my $sDigest (keys %digests) {
#        last if $oTrap->terminated();

        my @iInodes= @{$digests{$sDigest}};

        # ignore digests with only one inode
        next if scalar @iInodes == 1;
    
        # map files to inodes
        my %FilesByInode= ();
        for my $iInode (@iInodes) {
#            last if $oTrap->terminated();
            $FilesByInode{$iInode}= $oStore->getFilesByInode($iInode);
        }
        
        $fLinkFiles->(\%FilesByInode);
    }
}

sub _linkFiles {
    my $self= shift;
    my $hFilesByInode= shift;

    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    # find inode with most hard links
    my $iMaxLinks= 0;
    my $iMaxInode= undef;
    my $sLinkFile;
    for my $iInode (keys %$hFilesByInode) {
#        last if $oTrap->terminated();

        my $aFiles= $hFilesByInode->{$iInode};
        next unless scalar @$aFiles;

        if (scalar @$aFiles > $iMaxLinks) {
            $iMaxLinks= scalar @$aFiles;
            $iMaxInode= $iInode;
            $sLinkFile= $aFiles->[0];
        }
    }
    
    return unless $self->_testFile($sLinkFile, $iMaxInode);

    # link all inodes with the most linked one
    for my $iInode (keys %$hFilesByInode) {
#            last if $oTrap->terminated();

        next if $iInode == $iMaxInode;

        my $bLinkError= 0;
        for my $sFile (@{$hFilesByInode->{$iInode}}) {
#                last if $oTrap->terminated();

            next unless $self->_testFile($sFile, $iInode);

            logger()->debug("ln -f '$sLinkFile' '$sFile'");
            next if $self->{OPTS}{pretend};
            
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
                logger()->warn("Failed to link file '$sLinkFile' -> '$sFile'");
                $bLinkError= 1;
                next;
            }
            $oStore->updateInodeFile($iMaxInode, $sFile);
        }

        # TODO: should inode be removed if not all directories are checked??
        $oStore->removeInode($iInode) unless $self->{OPTS}{pretend} || $bLinkError;
    }
}

sub _testFile {
    my $self= shift;
    my $sFile= shift;
    my $iInode= shift;
    unless (-f $sFile) {
        logger->error("File \"$sFile\" has disappeared.");
        return 0;
    }
    unless ((lstat $sFile)[1] == $iInode) {
        logger->error("File \"$sFile\" has changed inode.");
        return 0;
    }
    return 1;
}

sub run {
    my $self= shift;
    
    return unless $self->{INODE_CACHE}->collect();

    $self->dupmerge();

    $self->{INODE_CACHE}->finishInformationStore();

    $self->{INODE_CACHE}->printStats([
        {name => "total_size",         text => "Total file size in bytes"},
        {name => "linked_size",        text => "Freed space in bytes"},
        {name => "linked_files",       text => "Found duplicates"},
        {name => "linked_files_failed",text => "Failed duplicates"},
    ]);
}

1;