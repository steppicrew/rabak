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
        "ignore-perms" =>       [ "",  "", "",  "Ignore permissions" ],
        "ignore-owner" =>       [ "o", "", "",  "Ignore ownership" ],
        "ignore-time" =>        [ "t", "", "",  "Ignore file date/time" ],
        "ignore-zero-sized" =>  [ "",  "", "",  "Include files with zero byte size" ],

        "min-size" =>           [ "", "", "<min size>",         "Ignore files smaller than <min size>" ],
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
rabak dupmerge [options] <dir> [<dir>...]

Hardlinks identical files in the specified directories.

Use this command to eliminate identical files not already hard linked by rsync.
This may be useful after renaming or moving files to save disk space after backing up your data.
It creates an inode database and one database per given directory for later use and faster inode location.
$sOptions
__EOT__
}

sub run {
    my $self= shift;

    #TODO: implement option pretend (i.e. do not cache inodes but print possible hard links)
    $self->warnOptions([ 'pretend' ]);

    if (scalar @{ $self->{ARGS} } == 0) {
        $self->{ERROR}= "Please provide one or more directory paths!\n";
        return 0;
    }

    my @sDirs= @{ $self->{ARGS} };
    my $hAllowedOpts= $self->getOptions();
    # replace '-' in options with '_'
    my %sOpts = map {
        my $value= $self->{OPTS}->{$_};
        s/\-/_/g;
        $_ => $value;
    } grep {$hAllowedOpts->{$_}} keys %{$self->{OPTS}};
    $sOpts{dirs} = \@sDirs;

    my $dm= RabakLib::DupMerge->new(\%sOpts);

    $dm->run();

    return 1;
}

1;
