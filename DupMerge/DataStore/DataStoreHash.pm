package DupMerge::DataStore::DataStoreHash;

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(DupMerge::DataStore);

sub new {
    my $class= shift;
    
    my $self= $class->SUPER::new();
    $self->{SizeInodes}= {};
    $self->{InodeFiles}= {};
    
    bless $self, $class;
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    $self->SUPER::addInodeFile($iInode, $sName);
    
    $self->{InodeFiles}{$iInode}= {
        files => [],
    } unless exists $self->{InodeFiles}{$iInode};
    push @{$self->{InodeFiles}{$iInode}{files}}, $sName;
}

sub addInode {
    my $self= shift;
    my $iInode= shift;
    my $iSize= shift;
    my $iMode= shift;
    my $sOwner= shift;
    my $iMtime= shift;

    my $sKey= "${iSize}_${iMode}_${sOwner}_${$iMtime}";    
    $self->{SizeInodes}->{$iSize}{$sKey}= [] unless exists $self->{SizeInodes}->{$iSize}{$sKey};
    push @{$self->{SizeInodes}->{$iSize}{$sKey}}, $iInode;
}

sub getDescSortedSizes {
    my $self= shift;
    
    return [sort {$b <=> $a} keys(%{$self->{SizeInodes}})];
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    my $aKeys= shift;
    
    die "not yet implemented";
    return [keys %{$self->{SizeInodes}{$iSize}}];
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $hKey= shift;
    
    die "not yet implemented";
    return $self->{SizeInodes}{$iSize}{$hKey};
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{InodeFiles}{$iInode}{files};
}

sub getFileKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{InodeFiles}{$iInode}{key};
}

1;
