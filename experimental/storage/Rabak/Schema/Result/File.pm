#!/usr/bin/perl

# perldoc DBIx::Class::ResultSource

package Rabak::Schema::Result::Job;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('conf.file');
__PACKAGE__->add_columns(
        'file_name'         => { 'data_type' => 'TEXT' },
        'inode'             => { 'data_type' => 'INTEGER' },
        'backup_uuid'       => { 'data_type' => 'TEXT' },
);

__PACKAGE__->set_primary_key('file_name');

#        'backup_uuid' => { 'fkey' => [ 'backup', 'backup_uuid' ], 'type' => 'TEXT' },


1;
