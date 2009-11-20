#!/usr/bin/perl

package Rabak::Schema::ConfigResult;
use base qw/DBIx::Class/;

sub init {
    my $class= shift;
    my $db= shift;

    $class->load_components(qw/ Core /);
    $class->table($db . '.conf');
    $class->add_columns(
        'key'               => { 'data_type' => 'TEXT' },
        'value'             => { 'data_type' => 'TEXT' },
    );
    $class->set_primary_key('key');
}

1;
