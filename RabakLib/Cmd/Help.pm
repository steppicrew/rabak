#!/usr/bin/perl;

package RabakLib::Cmd::Help;

use warnings;
use strict;
use vars qw(@ISA);

use Data::Dumper;
use RabakLib::Version;

@ISA= qw( RabakLib::Cmd );

sub getOptions {
    return {
    };
}

sub ShortHelp {
    my $sCmd= shift;

    my $oCmd= RabakLib::Cmd::Build([ $sCmd ]);
    my $sHelp= $oCmd->help("");
    return "\n    $1\n    $2\n" if $sHelp =~ /^([^\n]+)\n\n([^\n]+)\n/;
    die "\n\nText in RabakLib::Cmd::" . ucfirst($sCmd) . "::help formatted badly!!\n\n";
}

sub help {
    shift;
    my $sOptions= shift;

    my $sCmds= ShortHelp('conf')
        . ShortHelp('backup')
        . ShortHelp('dupmerge')
        . ShortHelp('doc')
        . ShortHelp('version')
    ;
    # TODO: tutorial dupesearch archive

    return <<__EOT__;
Available commands:

    rabak help [options] [<command>]
    Displays more information about a given command.
$sCmds$sOptions
__EOT__

}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0, 1);

    $self->warnOptions();
    print RabakLib::Version::VersionMsg() unless $self->{ARGS}[0];

    my $sCmd= $self->{ARGS}[0] || 'help';
    my $oCmd= RabakLib::Cmd::Build([ $sCmd ]);

    print $/ . $oCmd->help($self->getOptionsHelp($self->GetGlobalOptions(), $oCmd->getOptions()));

    return 1;
}

1;
