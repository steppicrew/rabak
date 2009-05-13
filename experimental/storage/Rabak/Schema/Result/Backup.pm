#!/usr/bin/perl

package Rabak::Schema::Result::Backup;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.source_session');
__PACKAGE__->add_columns(
#        'backup_uuid' => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'target_datadir'    => { 'data_type' => 'TEXT' },
        'session_uuid'      => { 'data_type' => 'TEXT' },
);

#__PACKAGE__->set_primary_key('backup_uuid');

## __PACKAGE__->has_many('albums', 'Rabak::Schema::Result::Artist', 'album_id');

1;
