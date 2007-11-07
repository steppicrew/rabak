#!/usr/bin/perl

package DupMerge::DataStore;

use warnings;
use strict;

use vars qw(@ISA);

use DupMerge::DataStoreDB;
use DupMerge::DataStoreHash;

sub Factory {
    my $class= shift;
    my %params= @_;
    
    return DupMerge::DataStoreDB->new($params{temp_dir}) if $params{type} eq 'db';
    return DupMerge::DataStoreHash->new() if $params{type} eq 'hash';
    die "No DataStore type specified!";
}

sub new {
    my $class= shift;
    
    my $self= {
        inodes=> {},
    };
    bless $self, $class;
}

sub DESTROY {
    my $self= shift;
    return $self->destroy();
}

sub destroy { return undef; }

sub inodeExists {
    my $self= shift;
    my $iInode= shift;
    
    return exists $self->{inodes}{$iInode};
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sKey= shift;
    my $sName= shift;
    
    $self->{inodes}{$iInode}= undef;
}

# to be overwritten
sub addInodeSize { die "Sould have been overriden"; }
sub getDescSortedSizes { die "Sould have been overriden"; }
sub getKeysBySize { die "Sould have been overriden"; }
sub getInodesBySizeKey { die "Sould have been overriden"; }
sub getInodeFiles { die "Sould have been overriden"; }
sub getKeyByInode { die "Sould have been overriden"; }

sub beginWork {};
sub endWork {};

1;
