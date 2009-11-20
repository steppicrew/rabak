#!/usr/bin/perl

# perldoc DBIx::Class::ResultSource

package Rabak::Schema::Result::Job;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('conf.job');
__PACKAGE__->add_columns(
        'job_name'          => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'target_name'       => { 'data_type' => 'TEXT' },
        'target_url'        => { 'data_type' => 'TEXT' },
        'conf_filename'     => { 'data_type' => 'TEXT' },
);

__PACKAGE__->set_primary_key('job_name');

1;
