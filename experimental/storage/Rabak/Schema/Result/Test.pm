#!/usr/bin/perl

# perldoc DBIx::Class::ResultSource

package Rabak::Schema::Result::Test;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('test.test');
__PACKAGE__->add_columns(
        'test_id'           => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'url'               => { 'data_type' => 'TEXT' },
);
__PACKAGE__->set_primary_key('test_id');

1;
