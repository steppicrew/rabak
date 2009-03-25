#!/usr/bin/perl

package Rabak::InodeStore;

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
        "multidb" => "MultiDB",
    );
    my $sType= $params{type};
    my $sClassName= $classNames{$sType};
    my $new;
    die "No valid InodeStore type specified! - Internal error" unless $sClassName;
    eval {
        require "Rabak/InodeStore/$sClassName.pm";
        my $sClass= "Rabak::InodeStore::$sClassName";
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
    my $aInodes= shift || $self->getInodes();
    while (my $iInode= shift @$aInodes) {
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

sub getInodeDigest {
    my $self= shift;
    my $iInode= shift;
    
    return undef;
}

sub setInodeDigest {
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
sub addInode { die "Must be overriden"; }
sub getDescSortedSizes { die "Must be overriden"; }
sub getKeysBySize { die "Must be overriden"; }
sub getInodesBySizeKey { die "Must be overriden"; }
sub getInodeFiles { die "Must be overriden"; }
sub getFileKeyByInode { die "Must be overriden"; }
sub getCurrentFileCount { die "Must be overriden"; }

# may be overwritten
sub beginWork {};
sub endWork {};
sub commitTransaction {};

1;
