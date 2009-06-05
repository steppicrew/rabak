#!/usr/bin/perl

package Rabak::Schema::Result::Backup;
use base qw/Rabak::Schema::Result/;

use Data::Dumper;

# print Dumper(__PACKAGE__->add_columns);

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.backup');
__PACKAGE__->add_columns2(

        'backup_uuid'       => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'session_uuid'      => { 'data_type' => 'TEXT' },

        'target_df_start'   => { 'data_type' => 'INTEGER' },
        'target_df_end'     => { 'data_type' => 'INTEGER' },

        'target_metadir'    => { 'data_type' => 'TEXT' },
        'target_fullpath'   => { 'data_type' => 'TEXT' },
        'target_datadir'    => { 'data_type' => 'TEXT' },

        'time_start'        => { 'data_type' => 'TEXT' },
        'time_end'          => { 'data_type' => 'TEXT' },

        'src_name'          => { 'data_type' => 'TEXT' },

        'stats_text'        => { 'data_type' => 'TEXT' },
        'stats_total_files' => { 'data_type' => 'INTEGER' },
        'stats_failed_files' => { 'data_type' => 'INTEGER' },
        'stats_transferred_files' => { 'data_type' => 'INTEGER' },
        'stats_total_bytes' => { 'data_type' => 'INTEGER' },
        'stats_transferred_bytes' => { 'data_type' => 'INTEGER' },

        'url'               => { 'data_type' => 'TEXT' },
        'error_code'        => { 'data_type' => 'INTEGER' },
);

__PACKAGE__->set_primary_key('backup_uuid');

#            'session_uuid'      => { 'fkey' => [ 'session', 'session_uuid' ], 'data_type' => 'TEXT' },

## __PACKAGE__->has_many('albums', 'Rabak::Schema::Result::Artist', 'album_id');

1;

__END__

package Rabak::Schema::Result::Backup;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.backup');
__PACKAGE__->add_columns(

        'backup_uuid'       => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'session_uuid'      => { 'data_type' => 'TEXT' },

        'target_df_start'   => { 'data_type' => 'INTEGER' },
        'target_df_end'     => { 'data_type' => 'INTEGER' },

        'target_metadir'    => { 'data_type' => 'TEXT' },
        'target_fullpath'   => { 'data_type' => 'TEXT' },
        'target_datadir'    => { 'data_type' => 'TEXT' },

        'time_start'        => { 'data_type' => 'TEXT' },
        'time_end'          => { 'data_type' => 'TEXT' },

        'src_name'          => { 'data_type' => 'TEXT' },

        'stats_text'        => { 'data_type' => 'TEXT' },
        'stats_total_files' => { 'data_type' => 'INTEGER' },
        'stats_failed_files' => { 'data_type' => 'INTEGER' },
        'stats_transferred_files' => { 'data_type' => 'INTEGER' },
        'stats_total_bytes' => { 'data_type' => 'INTEGER' },
        'stats_transferred_bytes' => { 'data_type' => 'INTEGER' },

        'url'               => { 'data_type' => 'TEXT' },
        'error_code'        => { 'data_type' => 'INTEGER' },
);

__PACKAGE__->set_primary_key('backup_uuid');

#            'session_uuid'      => { 'fkey' => [ 'session', 'session_uuid' ], 'data_type' => 'TEXT' },

## __PACKAGE__->has_many('albums', 'Rabak::Schema::Result::Artist', 'album_id');

1;
