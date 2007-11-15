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
    my $sKey= shift;
    my $sName= shift;
    
    $self->SUPER::addInodeFile($iInode, $sKey, $sName);
    
    $self->{InodeFiles}{$iInode}= {
        key => $sKey,
        files => [],
    } unless exists $self->{InodeFiles}{$iInode};
    push @{$self->{InodeFiles}{$iInode}{files}}, $sName;
}

sub addInodeSize {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    my $iInode= shift;
    
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
    
    return [keys %{$self->{SizeInodes}{$iSize}}];
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    
    return $self->{SizeInodes}{$iSize}{$sKey};
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{InodeFiles}{$iInode}{files};
}

sub getKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{InodeFiles}{$iInode}{key};
}

1;
