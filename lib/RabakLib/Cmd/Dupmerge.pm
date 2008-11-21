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

        "min-size" =>           [ "", "=i", "<min size>",         "Ignore files smaller than <min size>" ],
        "max-size" =>           [ "", "=i", "<max size>",         "Ignore files larger than <max size>" ],
        "temp-dir" =>           [ "", "=s", "<temp dir>",         "Working directory for temporary data collection (default: '/tmp')" ],
        "db-backend" =>         [ "", "=s", "<db engine>",        "Database engine. possible values: sqlite2, sqlite3 (default)" ],
        "db-inodes-dir" =>      [ "", "=s", "<dir>",              "Directory for inodes.db (default: current dir)" ],
        "db-postfix" =>         [ "", "=s", "<multi db postfix>", "Enables db for each directory. Specifies postfix for db name" ],
    };
}

sub Help {
    my $self= shift;
    return $self->SUPER::Help(
        'rabak dupmerge [options] <dir> [<dir>...]',
        'Hardlinks identical files in the specified directories.',
        'Use this command to eliminate identical files not already hard linked by rsync.',
        'This may be useful after renaming or moving files to save disk space after backing up your data.',
    );
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
