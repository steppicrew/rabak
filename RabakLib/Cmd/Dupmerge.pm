#!/usr/bin/perl;

package RabakLib::Cmd::Dupmerge;

use warnings;
use strict;

use Data::Dumper;
use RabakLib::DupMerge;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

# TODO: skip-missing

sub getOptions {
    return {
        "span-devs" =>          [ "",  "", "",  "Continue when directories span multiple devices (but ignore them)\n"
                                                . "Program dies if parameter is not given and more than one device is used"],
        "ignore-perms" =>       [ "",  "", "",  "Ignore permissions" ],
        "ignore-owner" =>       [ "o", "", "",  "Ignore ownership" ],
        "ignore-time" =>        [ "t", "", "",  "Ignore file date/time" ],
        "zero-size" =>          [ "",  "", "",  "Include files with zero byte size" ],

        # FIXME: Sollte nur "smaller than" sein!
        "min-size" =>           [ "", "", "<min size>",         "Ignore files smaller than or equal <min size>" ],
        "max-size" =>           [ "", "", "<max size>",         "Ignore files larger than <max size>" ],
        "temp-dir" =>           [ "", "", "<temp dir>",         "Working directory for temporary data collection (default: '/tmp')" ],
        "db-backend" =>         [ "", "", "<db engine>",        "Database engine. possible values: sqlite2, sqlite3 (default)" ],
        "db-inodes-dir" =>      [ "", "", "",                   "Directory for inodes.db (default: current dir)" ],
        "db-postfix" =>         [ "", "", "<multi db postfix>", "Enables db for each directory. Specifies postfix for db name" ],
    };
}

sub help {
    shift;
    my $sOptions= shift;
    return <<__EOT__;
rabak dupemerge [options] <backup set>

one liner

description
$sOptions
__EOT__
}

sub run {
    my $self= shift;

    $self->warnOptions([ 'quiet', 'verbose', 'pretend' ]);

    if (scalar @{ $self->{ARGS} } == 0) {
        $self->{ERROR}= "Please provide one or more directory paths!\n";
        return 0;
    }

    my @sDirs= @{ $self->{ARGS} };
    my $dm= RabakLib::DupMerge->new({
        dirs            => \@sDirs,
        quiet           => $self->{OPTS}{'quiet'},
        verbose         => $self->{OPTS}{'verbose'},,
        dryrun          => $self->{OPTS}{'pretend'},

        ignore_devspans => $self->{OPTS}{'span-devs'},          # NOT ??????????
        ignore_perms    => $self->{OPTS}{'ignore-perms'},
        ignore_owner    => $self->{OPTS}{'ignore-owner'},
        ignore_time     => $self->{OPTS}{'ignore-time'},
        skip_zero       => $self->{OPTS}{'zero-size'},          # NOT ??????????
        min_size        => $self->{OPTS}{'min-size'},
        max_size        => $self->{OPTS}{'max-size'},
        temp_dir        => $self->{OPTS}{'temp-dir'},
        db_engine       => $self->{OPTS}{'db-backend'},
        base_dir        => $self->{OPTS}{'db-inodes-dir'},
        multi_db_postfix=> $self->{OPTS}{'db-postfix'},

        cb_infoS        => sub {print join "\n", @_; STDOUT->flush();}          # ????????
    });

    $dm->run();

    return 1;
}

1;
