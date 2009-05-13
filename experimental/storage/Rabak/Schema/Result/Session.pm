#!/usr/bin/perl

package Rabak::Schema::Result::Session;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.session');
__PACKAGE__->add_columns(
        'session_uuid'      => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'job_name'          => { 'data_type' => 'TEXT' },
);
__PACKAGE__->set_primary_key('session_uuid');

1;
