#!/usr/bin/perl

package RabakLib::Archive;

#TODO: change key for persistant inode_size db

use strict;
use warnings;

#use File::Find;
#use Data::Dumper;
#use Fcntl ':mode';
#use Digest::SHA1;
#use Cwd;

use RabakLib::Trap;
use RabakLib::Log;
use RabakLib::InodeStore;
use RabakLib::InodeCache;
use RabakLib::Conf;

sub new {
    my $class= shift;
    my $hOptions= shift;

    my $self= {};
    $self->{OPTS}= $hOptions;
    $self->{INODE_CACHE}= RabakLib::InodeCache->new($hOptions);
    
    bless $self, $class;
}

sub _run {
    my $self= shift;
    
    my $oTrap= RabakLib::Trap->new();

    logger()->info("Archiving...");
    
    my $oCache= $self->{INODE_CACHE};
    my $oStore= $oCache->{DS};

    $oStore->beginCached();






    logger()->info("...done");
    logger()->info("Finishing information store...");

    $oStore->endCached();
    $oStore->endWork();

    logger()->info("done");

    return !$oTrap->restore();
}

sub run {
    my $self= shift;
    
    my $oConf= RabakLib::Conf->new();
    $oConf->set_value("switch.verbose", $self->{OPTS}{verbose} ? 6 : 3);
    $oConf->set_value("switch.pretend", $self->{OPTS}{dryrun});
    $oConf->set_value("switch.quiet", $self->{OPTS}{quiet});
    logger()->init($oConf);

    return unless $self->{INODE_CACHE}->collect();

    $self->_run();

    $self->{INODE_CACHE}->printStats([
        {name => "total_size",         text => "Total file size in bytes"},
        {name => "linked_size",        text => "Freed space in bytes"},
        {name => "linked_files",       text => "Found duplicates"},
        {name => "linked_files_failed",text => "Failed duplicates"},
    ]);
}

1;

__END__

ideas etc...

./archive.pl ..2008-09-12
./archive.pl -l ..2008-09-12