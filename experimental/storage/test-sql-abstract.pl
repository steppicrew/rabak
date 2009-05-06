#!/usr/bin/perl

use SQL::Abstract;

my $sql = SQL::Abstract->new;

# my($stmt, @bind) = $sql->select($table, \@fields, \%where, \@order);

# my($stmt, @bind) = $sql->insert($table, \%fieldvals || \@values);
# my($stmt, @bind) = $sql->update($table, \%fieldvals, \%where);
# my($stmt, @bind) = $sql->delete($table, \%where);

# Then, use these in your DBI statements
# my $sth = $dbh->prepare($stmt);
# $sth->execute(@bind);

# Just generate the WHERE clause
# my($stmt, @bind) = $sql->where(\%where, \@order);

# Return values in the same order, for hashed queries
# See PERFORMANCE section for more details
# my @bind = $sql->values(\%fieldvals);

my $table= [
    'session.backup',
    'conf.source',
];
my @fields= (
    'backup.title',
    'source.source_name',
    'source.job_name',
);
my %where= ();
my @order= ();

my ($stmt, @bind) = $sql->select($table, \@fields, \%where, \@order);

print $stmt, "\n";
