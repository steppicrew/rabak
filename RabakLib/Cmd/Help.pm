#!/usr/bin/perl;

package RabakLib::Cmd::Help;

use warnings;
use strict;
use vars qw(@ISA);

use Data::Dumper;

@ISA= qw( RabakLib::Cmd );

sub getOptions {
    return {
        # "targetgroup-value" =>  [ "",  "s", "<value>",   "Save on device with targetgroup value <value>" ],
        # "ha" =>                 [ "",  "",  "",          "HA" ],
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

    my $sCmds= ShortHelp('conf') . ShortHelp('backup') . ShortHelp('doc');
    # TODO: tutorial dupesearch archive

    return <<__EOT__;
Available commands:

    rabak [options] help [<command>]
    Displays more information about a given command.
$sCmds$sOptions
__EOT__

}

sub Version {
    return "\nThis is Rabak, v0.0001 (FIXME!!)\nRabak is your powerful and reliable rsync based backup system.\n";
}

sub PrintLongVersion {
    my $version= Version();
    print <<__EOT__;
$version
Copyright 2007-2008, Stephan Hantigk & Dietrich Raisin

Rabak may be copied only under the terms of either the Artistic License or the
GNU General Public License, which may be found in the Perl 5 source kit.
__EOT__

# Complete documentation for Perl, including FAQ lists, should be found on
# this system using "man perl" or "perldoc perl".  If you have access to the
# Internet, point your browser at http://www.perl.org/, the Perl Home Page.

}

sub run {
    my $self= shift;

    return unless $self->wantArgs(0, 1);

    if (!$self->{ARGS}[0]) {
        if ($self->{OPTS}{version}) {
            $self->warnOptions([ 'version' ]);
            PrintLongVersion();
            return 1;
        }
#        if ($self->{OPTS}{help}) {
#            $self->{ARGS}[0] }, 
#        }
        $self->warnOptions();
        print Version();
    }
    else {
        $self->warnOptions();
    }

    my $sCmd= $self->{ARGS}[0] || 'help';
    my $oCmd= RabakLib::Cmd::Build([ $sCmd ]);

    print $/ . $oCmd->help($self->getOptionsHelp($self->GetGlobalOptions(), $oCmd->getOptions()));

    return 1;
}

1;
