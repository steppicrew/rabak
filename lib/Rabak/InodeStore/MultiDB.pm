package Rabak::InodeStore::MultiDB;

use warnings;
use strict;

use Data::Dumper;

use Rabak::InodeStore;
use Rabak::InodeStore::DBBackend;

use vars qw(@ISA);

@ISA = qw(Rabak::InodeStore);

sub new {
    my $class= shift;
    my $hParams= shift;
    
    my $self= $class->SUPER::new();
    $self->{dbfn_postfix}= $hParams->{db_postfix};
    $self->{db_backend}=   $hParams->{db_backend};
    $self->{temp_dir}=     $hParams->{temp_dir};

    $self->{dbs}= []; # array of db hashes
    $self->{current_db}= undef;

    my $sInodeFileName= $hParams->{inodes_db};
    $self->{inode_db}= Rabak::InodeStore::DBBackend->new(
        $sInodeFileName, $self->{db_backend}, $self->{temp_dir}
    );

    bless $self, $class;
    $self->{inode_db}->_initTables('inodes');
    return $self;
}

sub newDirectory {
    my $self= shift;
    my $sDirectory= shift;
    my $sDBFileName= shift;
    
    $self->SUPER::newDirectory($sDirectory);

    unless ($sDBFileName) {
        $sDBFileName= $sDirectory;
        $sDBFileName =~ s/\/+$//;
        $sDBFileName.= $self->{dbfn_postfix};
    }
    my $bDbIsNew= ! -f $sDBFileName;
    $self->{current_db}= Rabak::InodeStore::DBBackend->new(
        $sDBFileName, $self->{db_backend}, $self->{temp_dir}, {directory=> $sDirectory}
    );
    $self->{current_db}->_initTables('files_inode');
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

sub invalidate {
    my $self= shift;
    return unless $self->{current_db};
    $self->{current_db}->invalidate();
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

sub _loopFilesByInode {
    my $self= shift;
    my $iInode= shift;
    my $fFileOp= shift;
    
    for my $db (@{$self->{dbs}}) {
        my $sDirectory= $db->getData("directory");
        for my $sFile (@{$db->getFilesByInode($iInode)}) {
            my $sFullFileName= "$sDirectory/$sFile";
            if (-f $sFullFileName) {
                # check if inode is connected to this file
                my $iCurInode= (lstat($sFullFileName))[1];
                
                if ($iCurInode == $iInode) {
                    return $sFullFileName unless $fFileOp->($sFullFileName);
                    next;
                }
 
                warn "File '$sFullFileName' has changed inode!";
                # TODO: insert new inode if not existant
                if ($self->inodeExists($iCurInode)) {
                    $db->updateInodeFile($iCurInode, $sFile);
                }
                else {
                    $db->removeFile($sFile);
                }
            }
            else {
                warn "File '$sFullFileName' disappeared!";
                $db->removeFile($sFile);
            }
        }
    }
    return undef;
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    my @files= ();
    $self->_loopFilesByInode($iInode, sub{ push @files, @_ });
    return \@files;
}

sub getOneFileByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->_loopFilesByInode($iInode, sub{ 0 });
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

sub getInodeDigest {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{inode_db}->getInodeDigest($iInode);
}

sub setInodeDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->{inode_db}->setInodeDigest($iInode, $sDigest);
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
