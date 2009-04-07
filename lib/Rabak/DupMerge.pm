#!/usr/bin/perl

package Rabak::DupMerge;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

use Rabak::Trap;
use Rabak::Log;
use Rabak::InodeCache;

use Data::Dumper;

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

# generates function returning list of similar inodes per call
# or undef at end
sub dupMergeInodesIterator {
    my $self= shift;
    
    # build array of relevant properties
    my $aQueryKey= [];
    push @$aQueryKey, "mode" unless $self->{OPTS}{ignore_perms};
    push @$aQueryKey, "owner" unless $self->{OPTS}{ignore_owner};
    push @$aQueryKey, "mtime" unless $self->{OPTS}{ignore_time};

    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    my $aSizes= $oStore->getDescSortedSizes();
    
    my @qKeys= ();
    my $iSize;
    
    return sub {
        while (1) {
            # return next list of similar indoes (if any)
            if (scalar @qKeys) {
                my $hKey= shift @qKeys;
                my $aInodes= $oStore->getInodesBySizeKey($iSize, $hKey);
                
                my %hInodeData= map { $_ => $oCache->getDigest($_) } @$aInodes;
                
                return \%hInodeData;
            }
        
            $iSize= shift @$aSizes;
            # break if no valid size was found
            return undef unless defined $iSize;
            
            next unless $iSize || $self->{OPTS}{include_zero_sized};
            next if $self->{OPTS}{min_size} && $iSize < $self->{OPTS}{min_size};
            next if $self->{OPTS}{max_size} && $iSize > $self->{OPTS}{max_size};

            # get list of hashes with {key name => value of key} for given size
            push @qKeys, @{ $oStore->getKeysBySize($iSize, $aQueryKey) };
        }

    }
}

sub dupMergeProcessGenerator {
    my $self= shift;
    my $fInodesIterator= shift;
    
    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    my @iInodes= ();
    my $hInodes= {};
    
    my $iJobId= 0;
    my $iLastJobId= 1;
    
    my $hInodeDigestsPerJob= {};
    
    my @qCommands= ();
    
    # fGetInput 1 returns command for execution ('digest' for digest calculation, 'hardlink' for hardlinking)
    # pre-inserts indodes with cached digests in $hInodeDigestsPerJob 
    my $fGetInput= sub {
        # first empty command queue (may be filled by $fProcessOutput)
        return shift @qCommands if scalar @qCommands;
        # next initiate digest's calculation
        while (1) {
            my $iInode= shift @iInodes;
            unless (defined $iInode) {
                $hInodes= $fInodesIterator->();
                unless (defined $hInodes) {
                    # return dummy command unless all jobs are done
                    return ['idle', $iJobId + 1] unless $iLastJobId >= $iJobId;
                    return undef;
                }
                
                @iInodes= keys %$hInodes;

                $iJobId++;
                $hInodeDigestsPerJob->{$iJobId}= {};
                next;
            }
            if ($hInodes->{$iInode}) {
                $hInodeDigestsPerJob->{$iJobId}{$iInode}= $hInodes->{$iInode};
                next;
            }
            
            return ['digest', $iJobId, $iInode, @{$oStore->getFilesByInode($iInode)}];
        }
    };
    
    # fProcessOutput 2 requeues processed commands
    # gets job id, inode and calculated digest
    my $fProcessOutput= sub {
        my $sCommand= shift;
        my @sParams= @_;
        
        if ($sCommand eq 'hardlink') {
            # do some output parsing
            return;
        }

        my $iThisJobId= shift @sParams;
        if ($sCommand eq 'digest') {
            my $iInode= shift @sParams;
            my $sDigest= shift @sParams;
            
            if ($sDigest) {
                $hInodeDigestsPerJob->{$iThisJobId}{$iInode}= $sDigest;
                $oStore->setInodeDigest($iInode, $sDigest);
            }
        }
        # process completely finished jobs
        while ($iLastJobId < $iThisJobId) {
            return unless $hInodeDigestsPerJob->{$iLastJobId};
            my %hInodes= %{$hInodeDigestsPerJob->{$iLastJobId}};
            # build list of inodes per digest
            my %hDigests= ();
            for my $iInode (keys %hInodes) {
                $hDigests{$hInodes{$iInode}}= [] unless $hDigests{$hInodes{$iInode}};
                push @{$hDigests{$hInodes{$iInode}}}, $iInode;
            }
            
            for my$sDigest (keys %hDigests) {
                my @iInodes= @{$hDigests{$sDigest}};
                # skip all digests with only one inode
                next unless scalar @iInodes > 1;
                my %hInodeFiles= map { $_ => $oStore->getFilesByInode($_) } @iInodes;
                push @qCommands, ['hardlink', %hInodeFiles];
            }
            
            delete $hInodeDigestsPerJob->{$iLastJobId};
            $iLastJobId++;
        }
        return;
    };
    
    return ($fGetInput, $fProcessOutput);
}

sub dupMerge {
    my $self= shift;
    my $oTrap= shift;
    
    logger()->info("Searching for duplicates...");
    logger()->incIndent();
    
    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    $oStore->beginCached();

    my $itInodes= $self->dupMergeInodesIterator();
    
    my ($fIn, $fOut)= $self->dupMergeProcessGenerator($itInodes);
    
    while (my $cmd= $fIn->()) {
#    # simulate much more $fIn-calls than $fOut-calls
#    while (my @cmds=map {$fIn->()} (1..50)) {
#    last unless $cmds[0];
#    while (my $cmd= shift @cmds) { 

        last if $oTrap && $oTrap->terminated();

        my @cmd= @$cmd;
        my $sCommand= shift @cmd;
        my @sCommandResult= ($sCommand);
        
        if ($sCommand eq 'digest') {
            my $iJobId= shift @cmd;
            my $iInode= shift @cmd;
            my @sFiles= @cmd;

            my $sDigest;
            if (scalar @sFiles) {
                logger->debug("Calculating digest for \"$sFiles[0]\"");
                $sDigest= $oCache->calcDigest($sFiles[0]) if scalar @sFiles;
            }
            # calculate digest for one of the files
            push @sCommandResult, $iJobId, $iInode, $sDigest;
        }
        elsif ($sCommand eq 'hardlink') {
            my %hInodeFiles= @cmd;
            my $iMaxInode= undef;
            my $iMaxInodeCount= 0;
            
            # sort inodes by link count descending
            # n.b.: inodes with no files are possible - filter out
            my @iInodes= sort {
                scalar(@{$hInodeFiles{$b}}) <=> scalar(@{$hInodeFiles{$a}})
            } grep { scalar @{$hInodeFiles{$_}} } keys %hInodeFiles;
            my $sLinkDest;
            while (my $iInode= shift @iInodes) {
                my @sFiles= @{$hInodeFiles{$iInode}};
                if ($sLinkDest && -f $sLinkDest) {
                    while (my $sFile= shift @sFiles) {
                        
                        next unless $self->_testFile($sFile, $iInode);

                        logger()->debug("ln -f '$sLinkDest' '$sFile'");
            
                        # find temporary file name
                        my $iTmpNum= "";
                        my $sTmpFile;
                        while (-e ($sTmpFile= "$sFile.tmp$iTmpNum")) { $iTmpNum++; }
                
                        # try to make sure no data is lost
                        unless (rename $sFile, $sTmpFile
                                and link $sLinkDest, $sFile
                                and unlink $sTmpFile
                        ) {
                            # if anything goes wrong, restore original file
                            if (-e $sTmpFile) {
                                unlink $sFile if -e $sFile;
                                rename $sTmpFile, $sFile;
                            }
                            logger()->warn("Failed to link file '$sLinkDest' -> '$sFile'");
                            last;
                        }
                        $oStore->updateInodeFile($iMaxInode, $sFile);
                    }
                }
                
                # there was an error linking files
                # assume more links to $sLinkDest are not possible
                if (scalar @sFiles) {
                    $sLinkDest= shift @sFiles;
                    $iMaxInode= $iInode;
                }
            }
        }
        else {
            # for all other commands pass input to output
            push @sCommandResult, @cmd;
        }
        $fOut->(@sCommandResult);
#    }
    }

    logger()->finish_progress("Processing files...done");
    logger()->decIndent();
    logger()->info("done");
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

    my $oTrap= Rabak::Trap->new();

    $self->dupMerge($oTrap);
    
    $oTrap->restore();

    $self->{INODE_CACHE}->finishInformationStore();
}

1;
