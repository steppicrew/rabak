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
sub addInodeSize {};
sub getSortedSizes { return []; }
sub getKeysBySize { return []; }
sub getInodesBySizeKey { return []; }
sub getInodeFiles { return []; }
sub getKeyByInode { return ''; }

sub beginWork {};
sub endWork {};
1;
