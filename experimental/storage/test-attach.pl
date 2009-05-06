#!/usr/bin/perl

use DBI;
use Data::Dumper;

my $dbh1 = DBI->connect("dbi:SQLite:dbname=:memory:");
my $dbh2 = DBI->connect("dbi:SQLite:dbname=:memory:");

#my $session0db = DBI->connect("dbi:SQLite:dbname=session0.db");

sub ex1 { print Dumper(($ret= $dbh1->prepare(join('', @_)))->execute); return $ret; }
sub ex2 { print Dumper(($ret= $dbh2->prepare(join('', @_)))->execute); return $ret; }

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
$sth= ex1("select * from t1 where num > 5");
            
while (@data = $sth->fetchrow_array()) {
    print Dumper(\@data);
};
                                               
                                                     