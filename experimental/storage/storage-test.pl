#!/usr/bin/perl

use strict;
use warnings;

use lib "../../lib";

use Data::Dumper;
use SQL::Abstract;

use Rabak::Log;
use Rabak::ConfFile;

use Data::Dumper;

my $dbpath= "/home/raisin/git/rabak.WORK/storage-test/";

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
    'medium' => {
        'fields' => {
            'medium_uuid' => { 'pkey' => 1, 'type' => 'TEXT' },
            'title' => { 'type' => 'TEXT' },
        },
        'location' => 'session',
        'provider' => sub {
        },
    },
    'session' => {
        'fields' => {
            'session_uuid' => { 'pkey' => 1, 'type' => 'TEXT' },
            'title' => { 'type' => 'TEXT' },
            'time_start' => { 'type' => 'TEXT' },
            'time_end' => { 'type' => 'TEXT' },
            'medium_uuid' => { 'fkey' => [ 'medium', 'medium_uuid' ], 'type' => 'TEXT' },
        },
        'location' => 'session',
    },
    'source_session' => {
        'fields' => {
            'source_session_uuid' => { 'pkey' => 1, 'type' => 'TEXT' },
            'title' => { 'type' => 'TEXT' },
            'url' => { 'type' => 'TEXT' },
            'time_start' => { 'type' => 'TEXT' },
            'time_end' => { 'type' => 'TEXT' },
            'session_uuid' => { fkey => [ 'session', 'session_uuid' ], 'type' => 'TEXT' },
        },
        'location' => 'session',
    },
    'file' => {
        'fields' => {
            'file_name' => { 'pkey' => 1, 'type' => 'TEXT' },
            'inode' => { 'type' => 'INTEGER' },
            'source_session_uuid' => { 'fkey' => [ 'source_session', 'source_session_uuid' ], 'type' => 'TEXT' },
        },
        'location' => 'session',
    },

    'job' => {
        'fields' => {
            'job_name' => { 'pkey' => 1, 'type' => 'TEXT' },
            'title' => { 'type' => 'TEXT' },
            'target_name' => { 'type' => 'TEXT' },
            'target_url' => { 'type' => 'TEXT' },
        },
        'location' => 'conf',
    },
    'source' => {
        'fields' => {
            'source_name' => { 'pkey' => 1, 'type' => 'TEXT' },
            'job_name' => { 'fkey' => [ 'job', 'job_name' ], 'type' => 'TEXT' },
            'url' => { 'type' => 'TEXT' },
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






package Table::source_session;

my $dbh;

sub db_exec {
    return shift->prepare(shift)->execute(@_);
}

sub db_insert {
    my $dbh= shift;
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
        db_exec($dbh, "INSERT INTO $table ("
                . join(',', @fields) . ') VALUES ('
                . join(',', map { '?' } @fields) . ')'
            , @values)
    }
}

sub _createTable {
    my $dbh= shift;
    my $table= shift;

    my $tableDef= $schema{$table} || die "Unknown table '$table'";

print "_createTable: $table\n";

    my @fields= ();
    while (my ($field, $def)= each %{ $tableDef->{'fields'} }) {
        push @fields, $field . " " . $def->{'type'}
            . ($def->{'pkey'} ? ' PRIMARY KEY' : '');
    }
    db_exec($dbh, 'DROP TABLE IF EXISTS ' . $table);
    db_exec($dbh, 'CREATE TABLE ' . $table . ' (' . join(',', @fields) . ')');
}

sub createTables {
    my $dbh= shift;
    my $location= shift;

    for (keys %schema) {
        _createTable($dbh, $_) if $schema{$_}{'location'} eq $location;
    }
}

sub db {
    my $oConf= ::_getConf();
    my @aJobs= Rabak::Job->GetJobs($oConf);

    $dbh= DBI->connect("dbi:SQLite:dbname=${dbpath}conf.db");
    createTables($dbh, 'conf');

    my $hJobs= {};
    for my $oJob (Rabak::Job->GetJobs($oConf)) {
        my $oTarget= $oJob->getTargetPeer();
        db_insert($dbh, 'job', {
            'job_name' => $oJob->getFullName(),
            'title' => $oJob->getValue('title'),
            'target_name' => $oTarget->getName(),
            'target_url' => $oTarget->getPath(),
        });

# print Data::Dumper->Dumper($oTarget); die;

        for my $oSource ($oJob->getSourcePeers()) {
            db_insert($dbh, 'source', {
                'source_name' => $oSource->getName(),
                'job_name' => $oJob->getFullName(),
                'url' => 'file:///' . $oSource->getFullName(),
            });
        }
    }
    
    return {
        error => 0,
        conf => {
            file => $oConf->filename(),
            title => $oConf->getValue('title') || '(Untitled Config)',
            jobs => $hJobs,
        }
    };
}

my $sessionsDbh;

sub query {
    my $args= shift;

    if ($args->{'where'}{'url'}) {
        # ...
    }
    if ($args->{'where'}{'session_uuid'}) {
        # ...
    }
}

package main;

Table::source_session::db();
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
