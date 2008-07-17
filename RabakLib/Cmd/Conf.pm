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

sub GetOptions {
    return {
        "targetgroup-value" =>  [ "",  "s", "<value>",   "Save on device with targetgroup value <value>" ],
        "ha" =>                 [ "",  "",  "",          "HA" ],
    };
}

sub run {
    my $self= shift;

    return if $self->want_args(0, 1);

    my $sBakSet= $self->{ARGS}[0] || '';
    if ($sBakSet eq '') {
        my $oConfFile= $self->readConf();
        $oConfFile->print_set_list();
        return 1;
    }
    if ($sBakSet eq '*') {
        my $oConfFile= $self->readConf();
        $oConfFile->print_all();
        return 1;
    }

#    my $hBakSet= _cmd_setup($sBakSet, 1);
#    $oConf->set_value("*.switch.warn_on_remote_access", 1);
#    my @sConf= @{ $hBakSet->show() };
#    pop @sConf;  # remove last []. (See RabalLib::Conf:show)
#    print join "\n", @sConf, "";
#    exit 0;

    return 1;
}

1;
