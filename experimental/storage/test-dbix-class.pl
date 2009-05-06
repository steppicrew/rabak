#!/usr/bin/perl

package Rabak::Schema;
use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_namespaces();

# By default this loads all the Result (Row) classes in the
# My::Schema::Result:: namespace, and also any resultset classes in the
# My::Schema::ResultSet:: namespace (if missing, the resultsets are
# defaulted to be DBIx::Class::ResultSet objects). You can change the
# result and resultset namespaces by using options to the
# L<DBIx::Class::Schema/load_namespaces> call.

# It is also possible to do the same things manually by calling
# C<load_classes> for the Row classes and defining in those classes any
# required resultset classes.

# Next, create each of the classes you want to load as specified above:

package Result::Schema::Result::Session;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.session');
__PACKAGE__->add_columns(
        'session_uuid'      => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'job_name'          => { 'data_type' => 'TEXT' },
);
__PACKAGE__->set_primary_key('session_uuid');


package Result::Schema::Result::SourceSession;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('session.backup');
__PACKAGE__->add_columns(
        'backup_uuid' => { 'data_type' => 'TEXT' },
        'title'             => { 'data_type' => 'TEXT' },
        'session_uuid'      => { 'data_type' => 'TEXT' },
);
__PACKAGE__->set_primary_key('backup_uuid');

## __PACKAGE__->has_many('albums', 'Rabak::Schema::Result::Artist', 'album_id');


package Result::Schema::Result::Source;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/ Core /);
__PACKAGE__->table('conf.source');
__PACKAGE__->add_columns(
        'source_name'       => { 'data_type' => 'TEXT' },
        'job_name'          => { 'data_type' => 'TEXT' },
        'url'               => { 'data_type' => 'TEXT' },
);
__PACKAGE__->set_primary_key('source_name');


package main;

my $schema = Rabak::Schema->connect("dbi:SQLite:dbname=:memory:");
my $storage= $schema->storage;

print $storage;

__END__

DBIx::Class doesn't directly use most of this data yet, but various related
modules such as L<DBIx::Class::WebForm> make use of it. Also it allows you to
create your database tables from your Schema, instead of the other way around.
See L<SQL::Translator> for details.

See L<DBIx::Class::ResultSource> for more details of the possible column
attributes.

Accessors are created for each column automatically, so My::Schema::Result::Album will
have albumid() (or album(), when using the accessor), artist() and title()
methods.

Define a primary key for your class:

  __PACKAGE__->set_primary_key('albumid');

If you have a multi-column primary key, just pass a list instead:

  __PACKAGE__->set_primary_key( qw/ albumid artistid / );

Define this class' relationships with other classes using either C<belongs_to>
to describe a column which contains an ID of another Table, or C<has_many> to
make a predefined accessor for fetching objects that contain this Table's
foreign key:

  __PACKAGE__->has_many('albums', 'My::Schema::Result::Artist', 'album_id');

See L<DBIx::Class::Relationship> for more information about the various types of
available relationships and how you can design your own.

=head2 Using L<DBIx::Class::Schema::Loader>

This is an external module, and not part of the L<DBIx::Class> distribution.
Like L<Class::DBI::Loader>, it inspects your database, and automatically creates
classes for all the tables in your database.  Here's a simple setup:

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( relationships => 1 );

  1;

The actual autoloading process will occur when you create a connected instance
of your schema below.

See the L<DBIx::Class::Schema::Loader> documentation for more information on its
many options.

=head2 Connecting

To connect to your Schema, you need to provide the connection details.  The
arguments are the same as for L<DBI/connect>:

  my $schema = My::Schema->connect('dbi:SQLite:/home/me/myapp/my.db');

You can create as many different schema instances as you need. So if you have a
second database you want to access:

  my $other_schema = My::Schema->connect( $dsn, $user, $password, $attrs );

Note that L<DBIx::Class::Schema> does not cache connections for you. If you use
multiple connections, you need to do this manually.

To execute some sql statements on every connect you can add them as an option in
a special fifth argument to connect:

  my $another_schema = My::Schema->connect(
      $dsn,
      $user,
      $password,
      $attrs,
      { on_connect_do => \@on_connect_sql_statments }
  );

See L<DBIx::Class::Schema::Storage::DBI/connect_info> for more information about
this and other special C<connect>-time options.

=head2 Basic usage

Once you've defined the basic classes, either manually or using
L<DBIx::Class::Schema::Loader>, you can start interacting with your database.

To access your database using your $schema object, you can fetch a
L<DBIx::Class::Manual::Glossary/"ResultSet"> representing each of your tables by
calling the C<resultset> method.

The simplest way to get a record is by primary key:

  my $album = $schema->resultset('Album')->find(14);

This will run a C<SELECT> with C<albumid = 14> in the C<WHERE> clause, and
return an instance of C<My::Schema::Result::Album> that represents this row.  Once you
have that row, you can access and update columns:

  $album->title('Physical Graffiti');
  my $title = $album->title; # $title holds 'Physical Graffiti'

If you prefer, you can use the C<set_column> and C<get_column> accessors
instead:

  $album->set_column('title', 'Presence');
  $title = $album->get_column('title');

Just like with L<Class::DBI>, you call C<update> to commit your changes to the
database:

  $album->update;

If needed, you can throw away your local changes:

  $album->discard_changes if $album->is_changed;

As you can see, C<is_changed> allows you to check if there are local changes to
your object.

=head2 Adding and removing rows

To create a new record in the database, you can use the C<create> method.  It
returns an instance of C<My::Schema::Result::Album> that can be used to access the data
in the new record:

  my $new_album = $schema->resultset('Album')->create({ 
    title  => 'Wish You Were Here',
    artist => 'Pink Floyd'
  });

Now you can add data to the new record:

  $new_album->label('Capitol');
  $new_album->year('1975');
  $new_album->update;

Likewise, you can remove it from the database:

  $new_album->delete;

You can also remove records without retrieving them first, by calling delete
directly on a ResultSet object.

  # Delete all of Falco's albums
  $schema->resultset('Album')->search({ artist => 'Falco' })->delete;

=head2 Finding your objects

L<DBIx::Class> provides a few different ways to retrieve data from your
database.  Here's one example:

  # Find all of Santana's albums
  my $rs = $schema->resultset('Album')->search({ artist => 'Santana' });

In scalar context, as above, C<search> returns a L<DBIx::Class::ResultSet>
object.  It can be used to peek at the first album returned by the database:

  my $album = $rs->first;
  print $album->title;

You can loop over the albums and update each one:

  while (my $album = $rs->next) {
    print $album->artist . ' - ' . $album->title;
    $album->year(2001);
    $album->update;
  }

Or, you can update them all at once:

  $rs->update({ year => 2001 });

In list context, the C<search> method returns all of the matching rows:

  # Fetch immediately all of Carlos Santana's albums
  my @albums = $schema->resultset('Album')->search(
    { artist => 'Carlos Santana' }
  );
  foreach my $album (@albums) {
    print $album->artist . ' - ' . $album->title;
  }

We also provide a handy shortcut for doing a C<LIKE> search:

  # Find albums whose artist starts with 'Jimi'
  my $rs = $schema->resultset('Album')->search_like({ artist => 'Jimi%' });

Or you can provide your own C<WHERE> clause:

  # Find Peter Frampton albums from the year 1986
  my $where = 'artist = ? AND year = ?';
  my @bind  = ( 'Peter Frampton', 1986 );
  my $rs    = $schema->resultset('Album')->search_literal( $where, @bind );

The preferred way to generate complex queries is to provide a L<SQL::Abstract>
construct to C<search>:

  my $rs = $schema->resultset('Album')->search({
    artist  => { '!=', 'Janis Joplin' },
    year    => { '<' => 1980 },
    albumid => { '-in' => [ 1, 14, 15, 65, 43 ] }
  });



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
