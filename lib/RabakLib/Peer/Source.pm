#!/usr/bin/perl

package RabakLib::Peer::Source;

use warnings;
use strict;

use RabakLib::Log;
use RabakLib::Peer;

use vars qw(@ISA);

@ISA = qw(RabakLib::Peer);

=head1 DESCRIPTION

Source.pm is an abstract class for source objects (file, databases etc.).
It provides a static method 'Factory' to create specialized source objects 

=over 4

=cut

sub Factory {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $sPath= $oOrigConf->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        my $sType= $1;
        my $sPrefType= $oOrigConf->get_value("type");
        logger->warn("Type in source path ($sType) differs from specified type ($sPrefType).") if $sPrefType && $sType ne $sPrefType;
        $oOrigConf->set_value("type", $sType);
        $oOrigConf->set_value("path", $sPath);
    }
    my $sType= $oOrigConf->get_value("type");
    unless (defined $sType) {
       $sType= "file";
       $oOrigConf->set_value("type", $sType);
    } 
    $sType= ucfirst lc $sType;

    my $new;
    eval {
        require "RabakLib/Peer/Source/$sType.pm";
        my $sClass= "RabakLib::Peer::Source::$sType";
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
    my $sName= $self->get_value("path_extension", $self->getName());
    $sName=~ s/^\*/source/;
    return "" if $sName eq "";
    return ".$sName";
}

sub prepareBackup {
    my $self= shift;
    my $bPretend= shift;

    logger->info("Source: " . $self->getFullPath());
    logger->set_prefix($self->get_value("type"));
    return 0;
}
sub finishBackup {
    my $self= shift;
    my $iBackupResult= shift;
    my $bPretend= shift;
    
    logger->set_prefix();
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
    return $self->get_value("type") . "://" . $self->SUPER::getFullPath();
}

1;
