#!/usr/bin/perl

package DupMerge::DataStore;

use warnings;
use strict;

use vars qw(@ISA);

# use FindBin qw($Bin);

use File::Temp();

use Data::Dumper;

sub Factory {
    my $class= shift;
    my %params= @_;
    
    my %classNames= (
        "multidb" => "DataStoreMultiDB",
    );
    my $sType= $params{type};
    my $sClassName= $classNames{$sType};
    my $new;
    die "No valid DataStore type specified! - Internal error" unless $sClassName;
    eval {
        require "DupMerge/DataStore/$sClassName.pm";
        my $sClass= "DupMerge::DataStore::$sClassName";
        $new= $sClass->new(\%params);
        1;
    };
    die $@ if $@;

    return $new;
}

sub new {
    my $class= shift;
    
    my $self= {
        inodes=> {},
        current_dir=> undef,
    };
    bless $self, $class;
}

sub DESTROY {
    my $self= shift;
    $self->endWork();
}

sub inodeExists {
    my $self= shift;
    my $iInode= shift;
    
    return exists $self->{inodes}{$iInode};
}

sub registerInodes {
    my $self= shift;
    my $aInodes= shift;
    
    my $iInode= undef;
    while ($iInode= shift @$aInodes) {
        $self->{inodes}{$iInode}= undef;
    }
}

sub getInodeCount {
    my $self= shift;
    
    return scalar keys(%{$self->{inodes}})
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    $self->registerInodes([$iInode]);
}

sub updateInodeFile {}

sub getDirectory {
    my $self= shift;
    return $self->{current_dir};
}

sub newDirectory {
    my $self= shift;
    my $sDirectory= shift;
    
    $self->finishDirectory();
    $self->{current_dir}= $sDirectory;
    return 1;
};

sub finishDirectory {
    my $self= shift;
    $self->{current_dir}= undef;
};

sub getDigestByInode {
    my $self= shift;
    my $iInode= shift;
    
    return undef;
}

sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return undef;
}

sub getInodes {
    my $self= shift;
    
    return [];
}

sub getOneFileByInode {
    my $self= shift;
    my $iInode= shift;
    
    my $aFiles= $self->getFilesByInode($iInode);
    return undef unless scalar @$aFiles;
    return $aFiles->[0];
}

# has to be overwritten
sub addInode { die "Sould have been overriden"; }
sub getDescSortedSizes { die "Sould have been overriden"; }
sub getKeysBySize { die "Sould have been overriden"; }
sub getInodesBySizeKey { die "Sould have been overriden"; }
sub getInodeFiles { die "Sould have been overriden"; }
sub getFileKeyByInode { die "Sould have been overriden"; }
sub getCurrentFileCount { die "Sould have been overriden"; }

# may be overwritten
sub beginWork {};
sub endWork {};
sub commitTransaction {};

1;
