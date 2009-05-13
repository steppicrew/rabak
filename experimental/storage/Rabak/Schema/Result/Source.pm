#!/usr/bin/perl

# perldoc DBIx::Class::ResultSource

package Rabak::Schema::Result::Source;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('conf.source');
__PACKAGE__->add_columns(
        'source_name'       => { 'accessor' => 'sourceName', 'data_type' => 'TEXT' },
        'job_name'          => { 'accessor' => 'jobName', 'data_type' => 'TEXT' },
        'url'               => { 'accessor' => 'url', 'data_type' => 'TEXT' },
);
#__PACKAGE__->set_primary_key('source_name');

1;
