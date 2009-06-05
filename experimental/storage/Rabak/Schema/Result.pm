#!/usr/bin/perl

package Rabak::Schema::Result;
use base qw/DBIx::Class/;

# use Moose;

use Data::Dumper;

sub add_columns2 {
    my $class= shift;

    print Dumper(\@_);

    $class->add_columns(@_);
    
}

1;
