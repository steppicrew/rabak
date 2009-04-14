#!/usr/bin/perl

package Rabak::Peer::Source;

use warnings;
use strict;

use Rabak::Log;
use Rabak::Peer;

use vars qw(@ISA);

@ISA = qw(Rabak::Peer);

=head1 DESCRIPTION

Source.pm is an abstract class for source objects (file, databases etc.).
It provides a static method 'Factory' to create specialized source objects 

=over 4

=cut

sub Factory {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $sPath= $oOrigConf->getValue("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        my $sType= $1;
        my $sPrefType= $oOrigConf->getValue("type");
        logger->warn("Type in source path ($sType) differs from specified type ($sPrefType).") if $sPrefType && $sType ne $sPrefType;
        $oOrigConf->setValue("type", $sType);
        $oOrigConf->setValue("path", $sPath);
    }
    my $sType= $oOrigConf->getValue("type");
    unless (defined $sType) {
       $sType= "file";
       $oOrigConf->setValue("type", $sType);
    } 
    $sType= ucfirst lc $sType;

    my $new;
    eval {
        require "Rabak/Peer/Source/$sType.pm";
        my $sClass= "Rabak::Peer::Source::$sType";
        $new= $sClass->newFromConf($oOrigConf);
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            logger->error("Backup type \"$sType\" is not defined: $@");
        }
        else {
            logger->error("An error occured: $@");
        }
        return undef;
    }

    return $new;
}


# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return ('type', shift->SUPER::PropertyNames(), 'keep', 'path_extension', 'previous_path_extensions', 'inode_inventory', 'merge_duplicates');
}

sub getPathExtension {
    my $self= shift;
    my $sName= $self->getValue("path_extension", $self->getName());
    $sName=~ s/^\*/source/;
    return "" if $sName eq "";
    return ".$sName";
}

sub prepareBackup {
    my $self= shift;

    logger->info("Source: " . $self->getFullPath());
    logger->setPrefix($self->getValue("type"));
    return 0;
}
sub finishBackup {
    my $self= shift;
    my $iBackupResult= shift;
    
    logger->setPrefix();
    $self->cleanupTempfiles();
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    my @sSuperResult= @{$self->SUPER::show($hConfShowCache)};

    return [] unless @sSuperResult;

    return [
        "",
        "#" . "=" x 79,
        "# Source \"" . $self->getShowName() . "\": " . $self->getFullPath(),
        "#" . "=" x 79,
        @sSuperResult
    ];
}

sub getFullPath {
    my $self= shift;
    return $self->getValue("type") . "://" . $self->SUPER::getFullPath();
}

1;
