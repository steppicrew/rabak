#!/usr/bin/perl


# Frage: warum kein bless in Target.pm etc ???
# job_name sollte warscheinlich sein:
#   job_id = conf_file//job_name
# oder
#   job_url = file://host/conf_file#job_name


use strict;
use warnings;

use lib "../../lib";
use lib "rabak/lib";

use Data::Dumper;
use SQL::Abstract;

use Rabak::Log;
use Rabak::ConfFile;

use Data::Dumper;

use Carp ();
$SIG{__WARN__} = \&Carp::cluck;
$SIG{__DIE__} = \&Carp::cluck;

my $dbpath= "/home/raisin/git/rabak.WORK/develop-storage-test/";

sub dumper {
    return Dumper([ @_ ]);
}

sub _getConf {
    my $oConfFile= Rabak::ConfFile->new();
    return $oConfFile->conf(), $oConfFile->filename() if wantarray;
    return $oConfFile->conf();
}

my $cmd;

$cmd= {
    'job' => {
        'select' => [
            'job_name'
        ],
        'left-join' => {
            'session' => {
                'select' => '*',
                'limit' => 1,
                'order' => {
                    'source_session.time_start' => 'desc',
                },
                'inner-join' => {
                    'source_session' => {
                        'where' => [
                            [ 'error-count', '>', 0 ],
                        ],
                    },
                },
            },
            'session__count' => {
                'table' => 'session',
                'select' => 'count',
                'inner-join' => {
                    'source_session' => {
                        'where' => [
                            [ 'error-count', '>', 0 ],
                        ]
                    },
                },
            },
        },
    },
};

my %schema= (

    # == SESSION ===

    'medium' => {
        'fields' => {
            'medium_uuid'       => { 'pkey' => 1, 'type' => 'TEXT' },
            'title'             => { 'type' => 'TEXT' },
        },
        'location' => 'session',
    },
    'session' => {
        'fields' => {
            'session_uuid'      => { 'pkey' => 1, 'type' => 'TEXT' },
            'title'             => { 'type' => 'TEXT' },
            'job_name'          => { 'type' => 'TEXT' },

            'target_name'       => { 'type' => 'TEXT' },
            'target_uuid'       => { 'type' => 'TEXT' },
            'target_url'        => { 'type' => 'TEXT' },

            'time_start'        => { 'type' => 'TEXT' },
            'time_end'          => { 'type' => 'TEXT' },

            'medium_uuid'       => { 'fkey' => [ 'medium', 'medium_uuid' ], 'type' => 'TEXT' },

            'stats_total_files' => { 'type' => 'INTEGER' },
            'stats_failed_files' => { 'type' => 'INTEGER' },
            'stats_transferred_files' => { 'type' => 'INTEGER' },
            'stats_total_bytes' => { 'type' => 'INTEGER' },
            'stats_transferred_bytes' => { 'type' => 'INTEGER' },
        },
        'location' => 'session',
    },
    'source_session' => {
        'fields' => {
            'source_session_uuid' => { 'pkey' => 1, 'type' => 'TEXT' },
            'title'             => { 'type' => 'TEXT' },
            'session_uuid'      => { 'fkey' => [ 'session', 'session_uuid' ], 'type' => 'TEXT' },

            'target_df_start'   => { 'type' => 'INTEGER' },
            'target_df_end'     => { 'type' => 'INTEGER' },

            'target_metadir'    => { 'type' => 'TEXT' },
            'target_fullpath'   => { 'type' => 'TEXT' },
            'target_datadir'    => { 'type' => 'TEXT' },

            'time_start'        => { 'type' => 'TEXT' },
            'time_end'          => { 'type' => 'TEXT' },

            'source_name'       => { 'type' => 'TEXT' },

            'stats_text'        => { 'type' => 'TEXT' },
            'stats_total_files' => { 'type' => 'INTEGER' },
            'stats_failed_files' => { 'type' => 'INTEGER' },
            'stats_transferred_files' => { 'type' => 'INTEGER' },
            'stats_total_bytes' => { 'type' => 'INTEGER' },
            'stats_transferred_bytes' => { 'type' => 'INTEGER' },

            'url'               => { 'type' => 'TEXT' },
            'error_code'        => { 'type' => 'INTEGER' },
        },
        'location' => 'session',
    },
    'file' => {
        'fields' => {
            'file_name'         => { 'pkey' => 1, 'type' => 'TEXT' },
            'inode'             => { 'type' => 'INTEGER' },
            'source_session_uuid' => { 'fkey' => [ 'source_session', 'source_session_uuid' ], 'type' => 'TEXT' },
        },
        'location' => 'session',
    },

    # == CONF ===

    'job' => {
        'fields' => {
            'job_name'          => { 'pkey' => 1, 'type' => 'TEXT' },
            'title'             => { 'type' => 'TEXT' },
            'target_name'       => { 'type' => 'TEXT' },
            'target_url'        => { 'type' => 'TEXT' },
            'conf_filename'     => { 'type' => 'TEXT' },
        },
        'location' => 'conf',
    },
    'source' => {
        'fields' => {
            'source_name'       => { 'pkey' => 1, 'type' => 'TEXT' },
            'job_name'          => { 'fkey' => [ 'job', 'job_name' ], 'type' => 'TEXT' },
            'url'               => { 'type' => 'TEXT' },
        },
        'location' => 'conf',
    },
);

$cmd= {
    'file' => {
        'select' => [ 'inode', 'file_name' ],
        'where' => [
            [ 'file_name', 'regex', 'steppi.*idee' ],
        ],
        'inner-join' => {
            'source_session' => {
                'select' => [ 'time_start' ],
                'where' => [
                    [ 'url', '=', 'file:///lisa/' ],
                    [ 'time_start', '>=', '2009-02-01' ],
                ],
            },
        },
        'distinct' => 'inode',
        'order-by' => 'source_session.time_start',
    }
};

print Dumper($cmd);

#------------------------------------------------------------------------------

package Object;

sub new {
    bless {}, shift;
}

#------------------------------------------------------------------------------

package DB;

use base 'Object';

sub new {
    my $class= shift;

    my $self= $class->SUPER::new(@_);
    $self->{DBH}= undef;

    bless $self, $class;
}

sub connect {
    my $self= shift;
    my $dbfile= shift;

    return $self->{DBH}= DBI->connect("dbi:SQLite:dbname=$dbfile");
}

sub execute {
    my $self= shift;

    return $self->{DBH}->prepare(shift)->execute(@_);
}

sub insert {
    my $self= shift;
    my $table= shift;
    my $data= shift;

    $data= [ $data ] unless ref $data eq 'ARRAY';
    my @fields= ();
    my @values= ();

    # TODO: can prepare statement once
    for (@$data) {
        while (my ($field, $value)= each %$_) {
            push @fields, $field;
            push @values, $value;
        }
        $self->execute("INSERT INTO $table ("
                . join(',', @fields) . ') VALUES ('
                . join(',', map { '?' } @fields) . ')'
            , @values)
    }
}

sub _createTable {
    my $self= shift;
    my $table= shift;

    my $tableDef= $schema{$table} || die "Unknown table '$table'";

print "_createTable: $table\n";

    my @fields= ();
    while (my ($field, $def)= each %{ $tableDef->{'fields'} }) {
        push @fields, $field . " " . $def->{'type'}
            . ($def->{'pkey'} ? ' PRIMARY KEY' : '');
    }
    $self->execute('DROP TABLE IF EXISTS ' . $table);
    $self->execute('CREATE TABLE ' . $table . ' (' . join(',', @fields) . ')');
}

sub createTables {
    my $self= shift;
    my $location= shift;

    for (keys %schema) {
        $self->_createTable($_) if $schema{$_}{'location'} eq $location;
    }
}

sub new_instance {
    my $self= shift;
    my $class= shift;
    my $instanceRef= shift;

    return $$instanceRef if $$instanceRef;

    $self= $class->SUPER::new(@_);
    bless $self, $class;

    $self->_build_db();
    return $$instanceRef= $self;
}

#------------------------------------------------------------------------------

package DB::Conf;

use base 'DB';

# Singleton
# TODO: Need a DB::Conf per conf file. For now this always uses the default conf file.

our $instance;

sub new {
    my $class= shift;
    return $class->SUPER::new_instance($class, \$instance);
}

sub _build_db {
    my $self= shift;

    my ($oConf, $sConfFilename)= ::_getConf();
    my @aJobs= Rabak::Job->GetJobs($oConf);

    $self->connect("${dbpath}conf.db");
    $self->createTables('conf');

    for my $oJob (Rabak::Job->GetJobs($oConf)) {

        my $oTargetPeer= $oJob->getTargetPeer();
        $self->insert('job', {
            'job_name'          => $oJob->getFullName(),
            'title'             => $oJob->getValue('title'),
            'target_name'       => $oTargetPeer->getName(),
            'target_url'        => $oTargetPeer->getPath(),
            'conf_filename'     => $sConfFilename,
        });

        for my $oSourcePeer ($oJob->getSourcePeers()) {
            $self->insert('source', {
                'source_name'   => $oSourcePeer->getName(),
                'job_name'      => $oJob->getFullName(),
                'url'           => 'file:///' . $oSourcePeer->getFullName(),
            });
        }
    }
}

#unused
sub query {
    my $args= shift;

    if ($args->{'where'}{'url'}) {
        # ...
    }
    if ($args->{'where'}{'session_uuid'}) {
        # ...
    }
}

#------------------------------------------------------------------------------

package DB::Session;

use base 'DB';

# Singleton
# TODO: Need a DB::Conf per conf file. For now this always uses the default conf file.

our $instance;

sub new {
    my $class= shift;
    return $class->SUPER::new_instance($class, \$instance);
}

sub _build_db {
    my $self= shift;

    my $oConf= ::_getConf();
    my @aJobs= Rabak::Job->GetJobs($oConf);
    my $sMetaDir= Rabak::Job->GetMetaBaseDir();

    $self->connect("${dbpath}session.db");
    $self->createTables('session');

    for my $oJob (@aJobs) {
        my $oTargetPeer= $oJob->getTargetPeer();
        my $sJobName= $oJob->getFullName();

        # FIXME: Was ist wenn der Job-Name nicht mehr exisitert?? Oops!!

        for my $sSessionFile (glob "$sMetaDir/*/$sJobName/session.*") {
            my $sSessionName= $sSessionFile;
            $sSessionName=~ s/.*\///;

            my $hSession= Rabak::ConfFile->new($sSessionFile)->conf()->getValues();

            my %hStats= (
                'total_bytes' => 0,
                'transferred_bytes' => 0,
                'total_files' => 0,
                'transferred_files' => 0,
                'failed_files' => 0,
            );
            for (my $i= 0; ; $i++) {
                my $hSource= $hSession->{"source_$i"} || last;
                $self->insert('source_session', {
                    'source_session_uuid' => rand(),         # FIXME: real uuid

                    'session_uuid'      => '123456',         # FIXME: real uuid

                    'target_df_start'   => $hSource->{'target'}{'df'}{'start'},
                    'target_df_end'     => $hSource->{'target'}{'df'}{'end'},

                    'target_metadir'    => $hSource->{'target'}{'metadir'},
                    'target_fullpath'   => $hSource->{'target'}{'fullpath'},
                    'target_datadir'    => $hSource->{'target'}{'datadir'},

                    'time_start'        => $hSource->{'time'}{'start'},
                    'time_end'          => $hSession->{'time'}{'end'},

                    'source_name'       => $hSource->{'fullname'},

                    'stats_text'                => $hSource->{'stats'}{'text'},
                    'stats_total_files'         => $hSource->{'stats'}{'total_files'},
                    'stats_failed_files'        => $hSource->{'stats'}{'failed_files'},
                    'stats_transferred_files'   => $hSource->{'stats'}{'transferred_files'},
                    'stats_total_bytes'         => $hSource->{'stats'}{'total_bytes'},
                    'stats_transferred_bytes'   => $hSource->{'stats'}{'transferred_bytes'},

                    'url' => $hSource->{'path'},
                    'error_code' => $hSource->{'result'},
                });

                $hStats{$_} += $hSource->{'stats'}{$_} || 0  for keys %hStats;
            }

            my %hSessionFields= (
                'session_uuid' => rand(),         # FIXME: real uuid
                'job_name'      => $sJobName,
                'target_name'   => $oTargetPeer->getName(),
                'target_url'    => $oTargetPeer->getPath(),
                'target_uuid'   => $hSession->{'target'}{'uuid'},
                'time_start'    => $hSession->{'time'}{'start'},
                'time_end'      => $hSession->{'time'}{'end'},
            );
            $hSessionFields{"stats_$_"}= $hStats{$_}  for keys %hStats;
            $self->insert('session', \%hSessionFields);
        }
    }
}

#------------------------------------------------------------------------------

package main;

my $oConfDb= DB::Conf->new();
my $oSessionDb= DB::Session->new();
die "DONE";

sub _ex {
    my $cmd= shift;
    my $parent_location= shift;

    for (keys %$cmd) {
        my $sel= $cmd->{$_};

        my $table= $sel->{'table'} || $_;
        my $table_location= $schema{$table}{'location'} || die "'$table' not a table in schema";

        if ($parent_location ne $table_location) {
        }

        if ($sel->{'left-join'}) {
die;
            my $res= _ex(\%{ $sel->{'left-join'} }, $table_location);
            next;
        }
        if ($sel->{'inner-join'}) {
            my $res= _ex(\%{ $sel->{'inner-join'} }, $table_location);
            next;
        }
    }
}

sub ex {
    my %cmd= @_;
    _ex(\%cmd);
}

ex(%$cmd);

die "NORMAL EXIT";

# ---

use DBI;
use Data::Dumper;

my $dbh1 = DBI->connect("dbi:SQLite:dbname=:memory:");
my $dbh2 = DBI->connect("dbi:SQLite:dbname=:memory:");

#my $session0db = DBI->connect("dbi:SQLite:dbname=session0.db");

sub ex1 { print Dumper((my $ret= $dbh1->prepare(join('', @_)))->execute); return $ret; }
sub ex2 { print Dumper((my $ret= $dbh2->prepare(join('', @_)))->execute); return $ret; }

ex1("attach database 'session0.db' as s0db");
ex1("attach database 'session1.db' as s1db");
ex1("attach database 'session2.db' as s2db");

ex1("create table files (inode INTEGER, filename TEXT)"),

ex1("insert into files select * from
    (select distinct inode, filename from
        (select * from s0db.files_inode union select * from s1db.files_inode union select * from s2db.files_inode)
    )
"),

die;


ex1("create table t1 (data TEXT, num double);");
ex1("insert into t1(data, num) values ('test$_', $_)") for 3 .. 7;
my $sth= ex1("select * from t1 where num > 5");
            
while (my @data = $sth->fetchrow_array()) {
    print Dumper(\@data);
};
                                               


__END__

    file:
        regex = 'steppi.*idee'
        source-session:
            url = file:///lisa/
            time.start = 2009-02-01
            order-desc time.start
        distinct inode
        order-desc source-session.time.start

-- jobs with errors:

    count job:
        session:
            source-session:
                error-count > 0

    job:
        session:
            limit 1
            order-desc time.start
            source-session:
                error-count > 0
        count session:
            source-session:
                error-count > 0

    select * from job, 
        session:
            limit 1
            order-desc time.start
            source-session:
                error-count > 0
        count session:
            source-session:
                error-count > 0
