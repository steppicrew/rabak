#!/usr/bin/perl

use lib ".";

use SQL::DB qw(
    define_tables
    coalesce
    count
    max
    min
    sum
    LENGTH
    cast
    upper
    lower
    case
    EXISTS
    now
    nextval
    currval
    setval
);

#         use SQL::DB qw(define_tables count max);

         define_tables(
           [
             table  => 'cities',
             class  => 'City',
             column => [name => 'id',   type => 'INTEGER', primary => 1],
             column => [name => 'name', type => 'TEXT'],
             db => 'test',
           ],
           [
             table  => 'addresses',
             class  => 'Address',
             column => [name => 'id',   type => 'INTEGER', primary => 1],
             column => [name => 'kind', type => 'TEXT'],
             column => [name => 'city', type => 'INTEGER', ref => 'test.cities(id)', null => 1 ],
             db => 'test',
           ],
           [
             table  => 'persons',
             class  => 'Person',
             column => [name => 'id',      type => 'INTEGER', primary => 1],
             column => [name => 'name',    type => 'VARCHAR(255)'],
             column => [name => 'age',     type => 'INTEGER'],
             column => [name => 'address', type => 'INTEGER',
                                           ref  => 'test.addresses(id)',
                                           null => 1],
#             column => [name => 'parent',  type => 'INTEGER',
#                                           ref  => 'test.persons(id)',
#                                           null => 1],
             db => 'test',
             index  => 'name',
           ]
         );

         my $db = SQL::DB->new();

$db->set_sqldebug(4095);

         $db->connect("dbi:SQLite:dbname=:memory:");

         # $db->connect('dbi:SQLite:sqldbtest.db');

         $db->dbh->do("ATTACH DATABASE 'sqldbtest.db' AS test");

        # $db->deploy;

         my $cities    = $db->arow('cities');
         my $persons   = $db->arow('test.persons');
         my $addresses = $db->arow('test.addresses');

if (1) {
         $db->do(
           insert => [$cities->id, $cities->name],
           values => [1, 'Springfield'],  # Pg: [nextval('id')...
         );

         $db->do(
           insert => [$persons->id, $persons->name, $persons->age],
           values => [1, 'Homer', 43],
         );

         $db->do(
           insert => [$addresses->id, $addresses->kind, $addresses->city],
           values => [2, 'residential', 1],  # Pg: [nextval('id')...
         );
}


         $db->do(
           update => [$persons->set_address(2)],
           where  => $persons->name == 'Homer',
         );

         my $ans = $db->fetch1(
           select => [count($persons->name)->as('count_name'),
                         max($persons->age)->as('max_age')],
           from   => $persons,
           where  => $persons->age > 40,
         );

print $ans->as_string, "\n";

         # The following prints "Head count: 1 Max age:43"
         print 'Head count: '. $ans->count_name .
                 ' Max age: '. $ans->max_age ."\n";

         my @items = $db->fetch(
           select    => [$persons->name, $persons->age, $addresses->city],
           from      => $persons,
           left_join => $addresses,
           on        => $addresses->id == $persons->address,
           where     => ($addresses->city == 'Springfield') & ($persons->age > 40),
           order_by  => $persons->age->desc,
           limit     => 10,
         );

         # Give me "Homer(43) lives in Springfield"
         foreach my $item (@items) {
             print $item->name, '(',$item->age,') lives in ', $item->city, "\n";
         }



__END__

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
