package DupMerge::DataStore::DataStoreDB;

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(DupMerge::DataStore);

use DupMerge::DataStore::DataStoreDBBackend;

use File::Temp();

sub new {
    my $class= shift;
    my $hParams= shift;
    
    my $self= $class->SUPER::new();
    if ($hParams->{work_dir}) {
        $self->{work_dir_name}= $hParams->{work_dir};
        $self->{db_dir}= File::Temp::tempdir(DIR => $hParams->{work_dir}, CLEANUP => 1);
    }
    else {
        $self->{work_dir_name}= $self->{db_dir}= "/tmp";
    }

    $self->{db}= DupMerge::DataStore::DataStoreDBBackend->new(
        "$self->{db_dir}/inode_size.db",
        $hParams->{db_engine},
    );

    bless $self, $class;
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sKey= shift;
    my $sName= shift;
    
    $self->SUPER::addInodeFile($iInode, $sKey, $sName);
    
    return $self->{db}->addInodeFile($iInode, $sKey, $sName);
}

sub updateInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    $self->SUPER::updateInodeFile($iInode, $sName);
    
    return $self->{db}->updateInodeFile($iInode, $sName);
}

sub addInodeSize {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    my $iInode= shift;
    
    return $self->{db}->addInodeSize($iSize, $sKey, $iInode);
}

sub getDescSortedSizes {
    my $self= shift;
    
    return $self->{db}->getDescSortedSizes();
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    
    return $self->{db}->getKeysBySize($iSize);
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    
    return $self->{db}->getInodesBySizeKey($iSize, $sKey);
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{db}->getFilesByInode($iInode);
}

sub getKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{db}->getKeyByInode($iInode);
}

sub getDigestByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{db}->getDigestByInode($iInode);
}

sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->{db}->setInodesDigest($iInode, $sDigest);
}

sub removeInode {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->{db}->removeInode($iInode);
}

sub beginWork {
    my $self= shift;
    
    return $self->{db}->beginWork();
}

sub endWork {
    my $self= shift;
    
    $self->{db}->endWork();

    $self->{db}->unlink();

    return undef;
}

sub beginInsert {
    my $self= shift;
    
    return $self->{db}->beginInsert();
}

sub endInsert {
    my $self= shift;

    return $self->{db}->endInsert();    
}

1;
