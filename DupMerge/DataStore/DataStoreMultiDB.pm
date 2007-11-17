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
    $self->{dbfn_prefix}= $hParams->{db_prefix};
    $self->{db_engine}= $hParams->{db_engine};

    $self->{dbs}= []; # array of db hashes
    $self->{current_db}= undef;
    my $sInodeFileName= "$hParams->{work_dir}/inodes.db";
    $self->{inode_db}= DupMerge::DataStore::DataStoreDBBackend->new(
        $sInodeFileName, $self->{db_engine}
    );

    bless $self, $class;
}

sub newDirectory {
    my $self= shift;
    my $sDirectory= shift;
    
    $self->SUPER::newDirectory($sDirectory);
    my $sFileName= "$sDirectory/$self->{dbfn_prefix}file_inodes.db";
    my $bDbIsNew= ! -f $sFileName;
    $self->{current_db}= DupMerge::DataStore::DataStoreDBBackend->new(
        $sFileName, $self->{db_engine}, {directory=> $sDirectory}
    );
    push @{$self->{dbs}}, $self->{current_db};
    
    $self->{current_db}->beginInsert() if $bDbIsNew;
    
    # return true if db did not exist, false otherwise
    return $bDbIsNew;
}

sub finishDirectory {
    my $self= shift;
    
    return unless $self->{current_db};
    
    $self->{current_db}->endInsert();
    $self->SUPER::finishDirectory();
    $self->{current_db}= undef;
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
# to be removed
    my @sizes= ();
    for my $db (@{$self->{dbs}}) {
        my $aNewSizes= $db->getDescSortedSizes();
        my $idx= 0;
        my $iSize= shift @$aNewSizes;
        while (defined $iSize && $idx < scalar @sizes) {
            if ($sizes[$idx] < $iSize) {
                splice @sizes, $idx, 0, $iSize;
                $iSize= shift @$aNewSizes;
            }
            elsif ($sizes[$idx] == $iSize) {
                $iSize= shift @$aNewSizes;
            }
            $idx++;
        }
        push @sizes, $iSize if defined $iSize;
        push @sizes, @$aNewSizes if scalar @$aNewSizes;
    }

    return \@sizes;
# alternative:
    my %sizes= ();
    for my $db ($self->{dbs}) {
        my $aNewSizes= $db->getDescSortedSizes();
        map { $sizes{$_}= 1; } @$aNewSizes;
    }
    return [ sort { $b <=> $a } keys(%sizes) ];
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
        for my $sFile (@{$db->getFilesByInode($iInode)}) {
            if (-f "$sDirectory/$sFile") {
                # check if inode is connected to this file
                if ((lstat("$sDirectory/$sFile"))[1] == $iInode) {
                    push @files, "$sDirectory/$sFile";
                }
                else {
                    warn "File '$sDirectory/$sFile' has changed inode!";
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

sub beginInsert {
    my $self= shift;
    
    return $self->{inode_db}->beginInsert();
}

sub endInsert {
    my $self= shift;

    return $self->{inode_db}->endInsert();    
}

sub beginWork {
    my $self= shift;
    
    return $self->{inode_db}->beginWork();
}

sub endWork {
    my $self= shift;
    
    # delete current db (may be incomplete)
    $self->{current_db}->unlink() if $self->{current_db};

    my $db= undef;
    while ($db= shift @{$self->{dbs}}) {
        $db->endWork();
    }
    
    $self->{inode_db}->endWork() if $self->{inode_db};
    return undef;
}

sub terminate {
    my $self= shift;
    $self->endWork();
}

1;
