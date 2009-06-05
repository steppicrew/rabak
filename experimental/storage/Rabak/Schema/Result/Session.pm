#!/usr/bin/perl

package Rabak::Schema::Result::Session;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.session');
__PACKAGE__->add_columns(
        'session_uuid'      => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'job_name'          => { 'data_type' => 'TEXT' },

        'target_name'       => { 'data_type' => 'TEXT' },
        'target_uuid'       => { 'data_type' => 'TEXT' },
        'target_url'        => { 'data_type' => 'TEXT' },

        'time_start'        => { 'data_type' => 'TEXT' },
        'time_end'          => { 'data_type' => 'TEXT' },

        'medium_uuid'       => { 'data_type' => 'TEXT' },

        'stats_total_files' => { 'data_type' => 'INTEGER' },
        'stats_failed_files' => { 'data_type' => 'INTEGER' },
        'stats_transferred_files' => { 'data_type' => 'INTEGER' },
        'stats_total_bytes' => { 'data_type' => 'INTEGER' },
        'stats_transferred_bytes' => { 'data_type' => 'INTEGER' },
);
__PACKAGE__->set_primary_key('session_uuid');

#        'medium_uuid'       => { 'fkey' => [ 'medium', 'medium_uuid' ], 'data_type' => 'TEXT' },

1;
