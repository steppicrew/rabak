#!/usr/bin/perl;

package Rabak::Cmd::Help;

use warnings;
use strict;
use vars qw(@ISA);

use Data::Dumper;
use Rabak::Version;
use Rabak::Log;

@ISA= qw( Rabak::Cmd );

sub getOptions {
    return {
    };
}

sub GetAllCommands {
    return sort(
#        'admin',
        'backup',
        'conf',
        'doc',
#        'dot',
        'dupmerge',
        'help',
        'version',
    );
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak help [options] [<command>]',
        'Displays more information about a given command.',
        'Used with a command, help prints detailed information and options for this command.',
        'Used without a command, help prints an overview of all available commands.',
    );
}

sub getHelp {
    my $self= shift;
    my $sCmd= shift;

    my $oCmd= Rabak::Cmd::Build([ $sCmd ]);
    my @sHelp= $oCmd->Help();
    my @sOptions= $self->getOptionsHelp($self->GetGlobalOptions(), $oCmd->getOptions());
    shift @sOptions unless defined $sHelp[2];
    return (
        @sHelp,
        @sOptions,
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0, 1);

    $self->warnOptions([ ]);
    
    if ($self->{ARGS}[0]) {
        my @sHelp= $self->getHelp($self->{ARGS}[0]);
        logger->print('', shift(@sHelp));
        logger->print('', shift(@sHelp)) if scalar @sHelp;
        logger->print('', @sHelp, '') if scalar @sHelp;
    }
    else {
        logger->print(Rabak::Version::VersionMsg());
        logger->print('', 'Available commands:');
        for my $sCmd ($self->GetAllCommands()) {
            my @sHelp= $self->getHelp($sCmd);
            logger->print('', '    ' . shift(@sHelp));
            logger->print('    ' . shift(@sHelp)) if scalar @sHelp;
        }
        logger->print($self->getOptionsHelp($self->GetGlobalOptions()), '');
    }
    return 1;
}

1;
