#!/usr/bin/perl;

package RabakLib::Cmd::Conf;

use warnings;
use strict;

use Data::Dumper;

use RabakLib::Log;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

# sub new {
#     my $class= shift;
#     my $self= {};
#     bless $self, $class;
# }

sub getOptions {
    return {
         "all"    => [ "", "", "", "Prints the complete configuration" ],
         "filter" => [ "", "", "", "Prints rsync's filter rules" ],
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
            $self->readConfFile()->print_all();
            return 1;
        }
        $self->readConfFile()->print_set_list();
        return 1;
    }

    my ($oBakset, $oConf)= $self->getBakset($sBakset);
    return 0 unless $oBakset;

    ## FIXME: Muss das auch bei ($sBakset eq '') passieren?? Nee!
    $oConf->set_value("*.switch.warn_on_remote_access", 1);

    $oBakset->set_value('/*.switch.show_filter', $self->{OPTS}{filter});
    my @sConf= @{ $oBakset->show() };
    pop @sConf;  # remove last []. (See RabalLib::Conf::show)
    logger->print(@sConf);

    return 1;
}

1;