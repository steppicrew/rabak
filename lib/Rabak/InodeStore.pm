#!/usr/bin/perl

package Rabak::InodeStore;

use warnings;
use strict;

use vars qw(@ISA);

# use FindBin qw($Bin);

use File::Temp();
use Data::Dumper;
use Rabak::Log;

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
    my @sParams= @_;
    
    return undef unless exists $self->{inodes}{$iInode};
    return 1 unless @sParams;
    my $sHash= join "_", @sParams;
    return 1 if $self->{inodes}{$iInode} eq $sHash;
    logger->warn(
        "Inode $iInode has been changed ("
        . $self->{inodes}{$iInode} . " != $sHash). Updating."
    );
    delete $self->{inodes}{$iInode};
    return undef;
}

sub registerAllInodes {
    my $self= shift;
    return $self->{inodes}= $self->getInodes();
}

sub _registerInode {
    my $self= shift;
    my $iInode= shift;
    my @sParams= @_;
    
    $self->{inodes}{$iInode}= join "_", @sParams;
}

sub getInodeCount {
    my $self= shift;
    
    return scalar keys(%{$self->{inodes}})
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    my @sParams= @_;
    
    $self->_registerInode($iInode, @sParams);
}

sub updateInodeFile {}

# DETECTED UNUSED: getDirectory
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
    
    return {};
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
# DETECTED UNUSED: getInodeFiles
sub getInodeFiles { die "Must be overriden"; }
sub getFileKeyByInode { die "Must be overriden"; }
sub getCurrentFileCount { die "Must be overriden"; }

# may be overwritten
sub beginWork {};
sub endWork {};
sub commitTransaction {};

1;
