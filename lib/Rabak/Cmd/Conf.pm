#!/usr/bin/perl;

package Rabak::Cmd::Conf;

use warnings;
use strict;

use Data::Dumper;

use Rabak::Log;

use vars qw(@ISA);

@ISA= qw( Rabak::Cmd );

# sub new {
#     my $class= shift;
#     my $self= {};
#     bless $self, $class;
# }

sub getOptions {
    return {
         "all"          => [ "", "", "", "Prints the complete configuration" ],
         "filter"       => [ "", "", "", "Prints rsync's filter rules" ],
         "omit-default" => [ "", "", "", "Suppress output of default-section" ],
    };
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak conf [options] [<backup set>]',
        'Displays the effective configuration.',
        'If no argument is given, prints the available backup sets defined in the default',
        'configuration file or in the configuration file specified by the "--conf" option.',
        '',
        'If a backup set name is given as a argument, prints the details of that confi-',
        'guration. Note that the output itself is a valid configuration file.',
    );
}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0, 1);

    $self->warnOptions([ 'conf' ]);

    my $sBakset= $self->{ARGS}[0] || '';

    if ($sBakset eq '') {
        if ($self->{OPTS}{all}) {
            $self->readConfFile()->printAll();
            return 1;
        }
        my $oConfFile= $self->readConfFile();
        logger->print("Available backup sets in \"" . $oConfFile->filename() . "\":");
        $oConfFile->printSetList();
        return 1;
    }

    my ($oBakset, $oConf)= $self->getBakset($sBakset);
    return 0 unless $oBakset;

    ## FIXME: Muss das auch bei ($sBakset eq '') passieren?? Nee!
    $oConf->setValue("*.switch.warn_on_remote_access", 1);
    
    my $hConfShowCache= {};
    
    # if omit-default is given, mark all default values as shown and discard output
    if ($self->{OPTS}{"omit-default"}) {
        my $oDefaultConf= $oConf->getNode('default');
        $oDefaultConf->show($hConfShowCache) if $oDefaultConf;
    }

    $oBakset->setValue('/*.switch.show_filter', $self->{OPTS}{filter});
    my @sConf= @{ $oBakset->show($hConfShowCache) };
    pop @sConf;  # remove last []. (See RabalLib::Conf::show)
    logger->print(@sConf);

    return 1;
}

1;
