package DupMerge::DataStore::DataStoreMultiDB;

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(DupMerge::DataStore);

use DupMerge::DataStore::DataStoreDBBackend;
use Data::Dumper;

sub new {
    my $class= shift;
    my $hParams= shift;
    
    my $self= $class->SUPER::new();
    $self->{dbfn_postfix}= $hParams->{db_postfix};
    $self->{db_engine}= $hParams->{db_engine};
    $self->{temp_dir}= $hParams->{temp_dir};

    $self->{dbs}= []; # array of db hashes
    $self->{current_db}= undef;
    my $sInodeFileName= "$hParams->{base_dir}/inodes.db";
    $self->{inode_db}= DupMerge::DataStore::DataStoreDBBackend->new(
        $sInodeFileName, $self->{db_engine}, $self->{temp_dir}
    );

    bless $self, $class;
}

sub newDirectory {
    my $self= shift;
    my $sDirectory= shift;
    
    $self->SUPER::newDirectory($sDirectory);
    my $sFileName= $sDirectory;
    $sFileName =~ s/\/+$//;
    $sFileName.= $self->{dbfn_postfix};
    my $bDbIsNew= ! -f $sFileName;
    $self->{current_db}= DupMerge::DataStore::DataStoreDBBackend->new(
        $sFileName, $self->{db_engine}, $self->{temp_dir}, {directory=> $sDirectory}
    );
    push @{$self->{dbs}}, $self->{current_db};

    # return true if db did not exist, false otherwise
    return $bDbIsNew;
}

sub finishDirectory {
    my $self= shift;
    
    return unless $self->{current_db};
    
    $self->{current_db}->commitTransaction();
    $self->{current_db}= undef;
    $self->SUPER::finishDirectory();
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    $self->SUPER::addInodeFile($iInode, $sName);

    # remove directory from file name
    my $qsDirectory= quotemeta $self->{current_db}->getData("directory");
    $sName=~ s/^$qsDirectory\/*//;
    
    return $self->{current_db}->addInodeFile($iInode, $sName);
}

sub updateInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    $self->SUPER::updateInodeFile($iInode, $sName);
    
    for my $db (@{$self->{dbs}}) {
        my $qsDirectory= quotemeta $db->getData("directory");

        $db->updateInodeFile($iInode, $1) if $sName=~ /^$qsDirectory\/*(.*)$/;
    }
}

sub addInode {
    my $self= shift;
    my $iInode= shift;
    my $iSize= shift;
    my $iMode= shift;
    my $sOwner= shift;
    my $iMtime= shift;
    
    return $self->{inode_db}->addInode($iInode, $iSize, $iMode, $sOwner, $iMtime);
}

sub getDescSortedSizes {
    my $self= shift;
    
    return $self->{inode_db}->getDescSortedSizes();
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    my $aKeys= shift;
    
    return $self->{inode_db}->getKeysBySize($iSize, $aKeys);
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $hKeys= shift;

    return $self->{inode_db}->getInodesBySizeKey($iSize, $hKeys);
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    my @files= ();
    for my $db (@{$self->{dbs}}) {
        my $sDirectory= $db->getData("directory");
        my $sFile= undef;
        my $aFiles= $db->getFilesByInode($iInode);
        while ($sFile= shift @$aFiles) {
            if (-f "$sDirectory/$sFile") {
                # check if inode is connected to this file
                my $iCurInode= (lstat("$sDirectory/$sFile"))[1];
                if ($iCurInode == $iInode) {
                    push @files, "$sDirectory/$sFile";
                }
                else {
                    warn "File '$sDirectory/$sFile' has changed inode!";
                    # TODO: insert new inode if not existant
                    if ($self->inodeExists($iCurInode)) {
                        $db->updateInodeFile($iCurInode, $sFile);
                    }
                    else {
                        $db->removeFile($sFile);
                    }
                }
            }
            else {
                warn "File '$sDirectory/$sFile' disappeared!";
                $db->removeFile($sFile);
            }
        }
    }
    return \@files;
}

sub getOneFileByInode {
    my $self= shift;
    my $iInode= shift;
    
    for my $db (@{$self->{dbs}}) {
        my $sDirectory= $db->getData("directory");
        for my $sFile (@{$db->getFilesByInode($iInode)}) {
            if (-f "$sDirectory/$sFile") {
                # check if inode is connected to this file
                my $iCurInode= (lstat("$sDirectory/$sFile"))[1];
                if ($iCurInode == $iInode) {
                    return "$sDirectory/$sFile";
                }
                else {
                    warn "File '$sDirectory/$sFile' has changed inode!";
                    # TODO: insert new inode if not existant
                    if ($self->inodeExists($iCurInode)) {
                        $db->updateInodeFile($iCurInode, $sFile);
                    }
                    else {
                        $db->removeFile($sFile);
                    }
                }
            }
            else {
                warn "File '$sDirectory/$sFile' disappeared!";
                $db->removeFile($sFile);
            }
        }
    }
}

sub getFileKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    for my $db (@{$self->{dbs}}) {
        my $result= $db->getFileKeyByInode($iInode);
        return $result if defined $result;
    }
    return undef;
}

sub getCurrentFileCount {
    my $self= shift;
    
    return 0 unless $self->{current_db};
    return $self->{current_db}->getFileCount();
}

sub getInodes {
    my $self= shift;
    
    return [] unless $self->{inode_db};
    return $self->{inode_db}->getInodes();
}

sub getDigestByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{inode_db}->getDigestByInode($iInode);
}

sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->{inode_db}->setInodesDigest($iInode, $sDigest);
}

sub removeInode {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->{inode_db}->removeInode($iInode);
}

sub commitTransaction {
    my $self= shift;

    return $self->{inode_db}->commitTransaction();    
}

sub beginCached {
    my $self= shift;
    
    for my $db (@{$self->{dbs}}) {
        $db->beginCached();
    }
    return $self->{inode_db}->beginCached() if $self->{inode_db};
}

sub endCached {
    my $self= shift;

    for my $db (@{$self->{dbs}}) {
        $db->endCached();
    }
    
    return $self->{inode_db}->endCached() if $self->{inode_db};    
}

sub beginWork {
    my $self= shift;
    
    return $self->{inode_db}->beginWork();
}

sub endWork {
    my $self= shift;
    
    my $db= undef;
    while ($db= shift @{$self->{dbs}}) {
        $db->endWork();
    }
    
    # delete current db (may be incomplete)
    $self->{current_db}->unlink() if $self->{current_db} && $self->{current_db}->wasChanged();
    $self->{current_db}= undef;

    $self->{inode_db}->endWork() if $self->{inode_db};
    $self->{inode_db}= undef;
    return undef;
}

1;