#!/usr/bin/perl;

package RabakLib::Cmd::Conf;

use warnings;
use strict;

use Data::Dumper;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

# sub new {
#     my $class= shift;
#     my $self= {};
#     bless $self, $class;
# }

sub getOptions {
    return {
         "all" => [ "", "", "", "Prints the complete configuration" ],
    };
}

sub help {
    shift;
    my $sOptions= shift;
    return <<__EOT__;
rabak conf [options] [<backup set>]

Displays the effective configuration.

If no argument is given, prints the available backup sets defined in the default
configuration file or in the configuration file specified by the "--conf" option.

If a backup set name is given as a argument, prints the details of that confi-
guration. Note that the output itself is a valid configuration file.
$sOptions
__EOT__
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

    ## FIXME: Muss das auch bei ($sBakset eq '') passieren??
    $oConf->set_value("*.switch.warn_on_remote_access", 1);

    my @sConf= @{ $oBakset->show() };
    pop @sConf;  # remove last []. (See RabalLib::Conf::show)
    print join "\n", @sConf, "";

    return 1;
}

1;
