package SQL::DB;
use 5.006;
use strict;
use warnings;
use base qw(SQL::DB::Schema);
use Carp qw(carp croak confess cluck);
use DBI;
use UNIVERSAL qw(isa);
use Return::Value;
use SQL::DB::Row;
use SQL::DB::Cursor;


our $VERSION = '0.17';

our @EXPORT_OK = @SQL::DB::Schema::EXPORT_OK;
foreach (@EXPORT_OK) {
    no strict 'refs';
    *{$_} = *{'SQL::DB::Schema::'.$_};
}

# Define our sequence table
define_tables([
    table => 'sqldb',
    class => 'SQL::DB::Sequence',
    column => [name => 'name', type => 'VARCHAR(32)', unique => 1],
    column => [name => 'val', type => 'INTEGER'],
]);


# Tell each of the tables why type of DBI/Database we are connected to
sub _set_table_types {
    my $self = shift;

    foreach my $table ($self->tables) {
        $table->set_db_type($self->{sqldb_dbd});
    }
    return;
}


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = bless($class->SUPER::new(@_), $class);
    if (!eval {$self->table('sqldb');1;}) {
        $self->associate_table('sqldb');
    }
    return $self;
}


sub set_debug {
    my $self = shift;
    $self->{sqldb_debug} = shift;
    return;
}


sub debug {
    my $self = shift;
    return $self->{sqldb_debug};
}


sub set_sqldebug {
    my $self = shift;
    $self->{sqldb_sqldebug} = shift;
    return;
}


sub sqldebug {
    my $self = shift;
    return $self->{sqldb_sqldebug};
}


sub connect {
    my $self = shift;

    my ($dsn,$user,$pass,$attrs) = @_;
    $attrs->{PrintError} = 0;
    $attrs->{RaiseError} = 1;

    if (my $dbh = DBI->connect($dsn,$user,$pass,$attrs)) {
        $self->{sqldb_dbh} = $dbh;
    }
    else {
        croak $DBI::errstr;
    }

    $self->{sqldb_dsn}    = $dsn;
    $self->{sqldb_user}   = $user;
    $self->{sqldb_pass}   = $pass;
    $self->{sqldb_attrs}  = $attrs;
    $self->{sqldb_qcount} = 0;
    $self->{sqldb_txn}    = 0;

    $dsn =~ /^dbi:(.*):/;
    $self->{sqldb_dbd} = $1;

    $self->_set_table_types();

    warn "debug: connected to $dsn" if($self->{sqldb_debug});
    return $self->{sqldb_dbh};
}


sub connect_cached {
    my $self = shift;

    my ($dsn,$user,$pass,$attrs) = @_;

    if (my $dbh = DBI->connect_cached($dsn,$user,$pass,$attrs)) {
        $self->{sqldb_dbh} = $dbh;
    }
    else {
        croak $DBI::errstr;
    }

    $self->{sqldb_dsn}    = $dsn;
    $self->{sqldb_user}   = $user;
    $self->{sqldb_pass}   = $pass;
    $self->{sqldb_attrs}  = $attrs;
    $self->{sqldb_qcount} = 0;

    $dsn =~ /^dbi:(.*):/;
    $self->{sqldb_dbd} = $1;

    $self->_set_table_types();

    warn "debug: connect_cached to $dsn" if($self->{sqldb_debug});
    return $self->{sqldb_dbh};
}


sub dbd {
    my $self = shift;
    return $self->{sqldb_dbd} if($self->{sqldb_dbh});
    return;
}


sub dbh {
    my $self = shift;
    return $self->{sqldb_dbh};
}


# calculate which tables reference which other tables, and plan the
# deployment order accordingly.
sub _deploy_order {
    my $self     = shift;
    my @src      = grep {$_->name ne 'sqldb'} $self->tables;
    my $deployed = {};
    my @ordered  = ();
    my $count    = 0;
    my $limit    = scalar @src + 10;

    while (@src) {
        if ($count++ > $limit) {
            die 'Deployment calculation limit exceeded: circular foreign keys?';
        }

        my @newsrc = ();
        foreach my $table (@src) {
            my $deployable = 1;
            foreach my $c ($table->columns) {
                if (my $foreignc = $c->references) {
                    if ($foreignc->table == $table or # self reference
                        $deployed->{$foreignc->table->name}) {
                        next;
                    }
                    $deployable = 0;
                }
            }
        
            if ($deployable) {
#                warn "debug: ".$table->name.' => deploy list ' if($self->{sqldb_sqldebug});
                push(@ordered, $table);
                $deployed->{$table->name} = 1;
            }
            else {
                push(@newsrc, $table);
            }
        }
        @src = @newsrc;

    }
    return @ordered;
}


sub deploy_sql {
    my $self   = shift;
    my $sql    = '';

    foreach my $table ($self->_deploy_order) {
        $sql .= join("\n", $table->sql_create) . "\n";
    }
    return $sql;        
}


sub _create_tables {
    my $self = shift;
    $self->dbh || croak 'cannot _create_tables() before connect()';

    my @tables = @_;

    # Faster to do all of this inside a BEGIN/COMMIT block on
    # things like SQLite, and better that we deploy all or nothing
    # anyway.
    my $res = $self->txn(sub{
        TABLES: foreach my $table (@tables) {
            my $sth = $self->dbh->table_info('', '', $table->name, 'TABLE');
            if (!$sth) {
                die $DBI::errstr;
            }

            while (my $x = $sth->fetch) {
                if ($x->[2] eq $table->name) {
                    carp 'Table '. $table->name
                         .' already exists - not creating';
                    next TABLES;
                }
            }

            foreach my $action ($table->sql_create) {
                my $res;
                eval {$res = $self->dbh->do($action);};
                if (!$res or $@) {
                    die $self->dbh->errstr . ' query: '. $action;
                }
                warn "debug: $action" if($self->{sqldb_sqldebug});
            }

        }
    });
    return $res;
}


sub create_table {
    my $self = shift;
    my $name = shift;
    $self->dbh || croak 'cannot create_table() before connect()';

    my $res = $self->_create_tables($self->table($name));

    croak($res) unless($res);
    return $res;
}


sub _drop_tables {
    my $self = shift;
    $self->dbh || croak 'cannot _drop_tables() before connect()';

    my @tables = @_;

    my $res = $self->txn(sub{
        foreach my $table (@tables) {
            my $sth = $self->dbh->table_info('', '', $table->name, 'TABLE');
            if (!$sth) {
                die $DBI::errstr;
            }

            my $x = $sth->fetch;
            if ($x and $x->[2] eq $table->name) {
                my $action = 'DROP TABLE IF EXISTS '.$table->name.
                    ($self->{sqldb_dbd} eq 'Pg' ? ' CASCADE' : '');

                my $res;
                eval {$res = $self->dbh->do($action);};
                if (!$res or $@) {
                    die $self->dbh->errstr . ' query: '. $action;
                }
                warn 'debug: '.$action if($self->{sqldb_sqldebug});
            }
        }
    });

    return $res;
}


sub drop_table {
    my $self = shift;
    my $name = shift;

    my $res = $self->_drop_tables($self->table($name));

    croak($res) unless($res);
    return $res;
}


sub deploy {
    my $self = shift;
    $self->dbh || croak 'cannot deploy() before connect()';

    my @tables = $self->_deploy_order;

    if ($self->table('sqldb')) {
        unshift(@tables, $self->table('sqldb'));
    }

    my $res = $self->txn(sub{
        $self->_create_tables(@tables);

        foreach my $table (@tables) {
            $self->create_seq($table->name);
        }
    });

    croak $res unless($res);
    return 1;
}


sub _undeploy {
    my $self = shift;
    $self->dbh || croak 'cannot _undeploy() before connect()';

    my @tables = reverse $self->_deploy_order;
    my $res    = $self->_drop_tables(@tables, $self->table('sqldb'));

    croak $res unless($res);
    return $res;
}


sub query_as_string {
    my $self = shift;
    my $sql  = shift || confess 'query_as_string requires an argument';
    
    foreach (@_) {
        if (defined($_) and $_ =~ /[^[:graph:][:space:]]/) {
            $sql =~ s/\?/*BINARY DATA*/;
        }
        else {
            my $quote = $self->dbh->quote(
                defined $_ ? "$_" : undef # make sure it is a string
            );
            $sql =~ s/\?/$quote/;
        }
    }
    return $sql;
}


sub _do {
    my $self    = shift;
    my $prepare = shift || croak '_do($prepare)';
    my $query   = $self->query(@_);
    my $rv;

    eval {
        my $sth = $self->dbh->$prepare("$query");
        my $i = 1;
        foreach my $type ($query->bind_types) {
            if ($type) {
                $sth->bind_param($i, undef, $type);
                carp 'debug: binding param '.$i.' with '.$type if($self->{sqldb_debug} && $self->{sqldb_debug} > 1);
            }
            $i++;
        }
        $rv = $sth->execute($query->bind_values);
        $sth->finish();
    };

    if ($@ or !defined($rv)) {
        cluck "debug: croaking " if($self->{sqldb_debug});
        croak "$@: Query was:\n"
            . $self->query_as_string("$query", $query->bind_values);
    }

    carp 'debug: '. $self->query_as_string("$query", $query->bind_values)
         ." /* Result: $rv */" if($self->{sqldb_sqldebug});

    $self->{sqldb_qcount}++;
    return $rv;
}


sub do {
    my $self = shift;
    $self->dbh || croak 'cannot do before connect()';
    return $self->_do('prepare_cached', @_);
}


sub do_nopc {
    my $self = shift;
    $self->dbh || croak 'cannot do before connect()';
    return $self->_do('prepare', @_);
}


sub _fetch {
    my $self    = shift;
    my $prepare = shift || croak '_fetch($prepare)';
    my $query   = $self->query(@_);
    my $class   = eval {SQL::DB::Row->make_class_from($query->acolumns);};

    if ($@) {
        confess "SQL::DB::Row->make_class_from failed: $@";
    }

    my $sth;
    my $rv;

    eval {
        $sth = $self->dbh->$prepare("$query");
        my $i = 1;
        foreach my $type ($query->bind_types) {
            if ($type) {
                $sth->bind_param($i, undef, $type);
            }
            $i++;
        }
        $rv = $sth->execute($query->bind_values);
    };

    if ($@ or !defined($rv)) {
        confess "$@: Query was:\n"
            . $self->query_as_string("$query", $query->bind_values);
    }

    if (wantarray) {
        my $arrayref;
        eval {
            $arrayref = $sth->fetchall_arrayref();
        };
        if (!$arrayref or $@) {
            croak "$@: Query was:\n"
                . $self->query_as_string("$query", $query->bind_values);
        }

        $self->{sqldb_qcount}++;
        carp 'debug: (Rows: '. scalar @$arrayref .') '.
              $self->query_as_string("$query", $query->bind_values)
              if($self->{sqldb_sqldebug});
        return map {$class->new_from_arrayref($_)->_inflate} @{$arrayref};
    }

    $self->{sqldb_qcount}++;
    carp 'debug: (Cursor call) '.
          $self->query_as_string("$query", $query->bind_values)
          if($self->{sqldb_sqldebug});

    return SQL::DB::Cursor->new($sth, $class);
}


sub fetch {
    my $self = shift;
    $self->dbh || croak 'cannot fetch before connect()';
    return $self->_fetch('prepare_cached', @_);
}


sub fetch_nopc {
    my $self = shift;
    $self->dbh || croak 'cannot fetch before connect()';
    return $self->_fetch('prepare', @_);
}


sub fetch1 {
    my $self   = shift;
    $self->dbh || croak 'cannot fetch before connect()';
    my $cursor = $self->_fetch('prepare_cached', @_);
    my $obj    = $cursor->next;
    $cursor->_finish();
    return $obj;
}


sub fetch1_nopc {
    my $self   = shift;
    $self->dbh || croak 'cannot fetch before connect()';
    my $cursor = $self->_fetch('prepare', @_);
    my $obj    = $cursor->next;
    $cursor->_finish();
    return $obj;
}


sub txn {
    my $self = shift;
    my $subref = shift;
    (ref($subref) && ref($subref) eq 'CODE') || croak 'usage txn($subref)';

    my $rc;
    $self->{sqldb_txn}++;

    if ($self->{sqldb_txn} == 1) {
        eval {$rc = $self->dbh->begin_work;};
        if (!$rc) {
            my $err = $self->dbh->errstr;
            carp $err;
            return failure $err;
        }
        carp 'debug: BEGIN WORK (txn 1)' if($self->{sqldb_sqldebug});
    }
    else {
        carp 'debug: Begin Work (txn '.$self->{sqldb_txn}.')'
        if($self->{sqldb_sqldebug});
    }


    my $result = eval {local $SIG{__DIE__}; &$subref};

    if ($@) {
        my $tmp = $@;
        if ($self->{sqldb_txn} == 1) { # top-most txn
            carp 'debug: ROLLBACK (txn 1)' if($self->{sqldb_sqldebug});
            eval {$self->dbh->rollback};
        }
        else { # nested txn - die so the outer txn fails
            carp 'debug: FAIL Work (txn '.$self->{sqldb_txn}.'): '
                 . $tmp if($self->{sqldb_sqldebug});
            $self->{sqldb_txn}--;
            die $tmp;
        }
        $self->{sqldb_txn}--;
        return failure $tmp;
    }

    if ($self->{sqldb_txn} == 1) {
        carp 'debug: COMMIT (txn 1)' if($self->{sqldb_sqldebug});
        $rc = $self->dbh->commit;
        carp $self->dbh->errstr unless($rc);
    }
    else {
        carp 'debug: End Work (txn '.$self->{sqldb_txn}.')'
        if($self->{sqldb_sqldebug});
    }
    $self->{sqldb_txn}--;

    if ($result or (ref($result) && ref($result) eq 'Return::Value')) {
        return $result;
    }
    return success $result;
}


sub create_seq {
    my $self = shift;
    my $name = shift || croak 'usage: $db->create_seq($name)';

    $self->{sqldb_dsn} || croak 'Must be connected before calling create_seq';

    my $s = SQL::DB::Schema::ARow::sqldb->new;

    my $exists = $self->fetch1(
        select => $s->name,
        from   => $s,
        where  => $s->name == $name,
    );

    if (!$exists) {
        eval {
            $self->do(
                insert  => [$s->name, $s->val],
                values  => [$name, 0],
            );
        };
        
        croak "create_seq: $@" if($@);
    }
    return 1;
}


sub seq {
    my $self = shift;
    my $name = shift || croak 'usage: $db->seq($name)';
    my $count = shift || 1;

    if ($count> 1 and !wantarray) {
        croak 'you should want the full array of sequences';
    }

    $self->{sqldb_dsn} || croak 'Must be connected before calling seq';

    my $sqldb = SQL::DB::Schema::ARow::sqldb->new;
    my $seq;
    my $no_updates;

    eval {
        # Aparent MySQL bug - no locking with FOR UPDATE
        if ($self->{sqldb_dbd} eq 'mysql') {
            $self->dbh->do('LOCK TABLES sqldb WRITE, sqldb AS '.
                                    $sqldb->_alias .' WRITE');
        }

        $seq = $self->fetch1(
            select     => [$sqldb->val],
            from       => $sqldb,
            where      => $sqldb->name == $name,
            for_update => ($self->{sqldb_dsn} !~ m/sqlite/i),
        );

        croak "Can't find sequence '$name'" unless($seq);

        $no_updates = $self->do(
            update  => [$sqldb->val->set($seq->val + $count)],
            where   => $sqldb->name == $name,
        );

        if ($self->{sqldb_dbd} eq 'mysql') {
            $self->dbh->do('UNLOCK TABLES');
        }

    };

    if ($@ or !$no_updates) {
        my $tmp = $@;

        if ($self->{sqldb_dbd} eq 'mysql') {
            $self->dbh->do('UNLOCK TABLES');
        }

        croak "seq: $tmp";
    }


    if (wantarray) {
        my $start = $seq->val + 1;
        my $stop  = $start + $count - 1;
        return ($start..$stop);
    }
    return $seq->val + $count;
}


sub insert {
    my $self = shift;
    foreach my $obj (@_) {
        unless(ref($obj) and $obj->can('q_update')) {
            croak "Not an insertable object: $obj";
        }
        my ($arows, @inserts) = $obj->q_insert; # reference hand-holding
        foreach (@inserts) {
            $self->do(@$_);
        }
    }
    return 1;
}


sub update {
    my $self = shift;
    foreach my $obj (@_) {
        unless(ref($obj) and $obj->can('q_update')) {
            croak "Not an updatable object: $obj";
        }
        my ($arows, @updates) = $obj->q_update; # reference hand-holding
        if (!@updates) {
            carp "No update for object. Missing PRIMARY KEY?";
            next;
        }
        foreach (@updates) {
            $self->do(@$_);
        }
    }
    return 1;
}


sub delete {
    my $self = shift;
    foreach my $obj (@_) {
        unless(ref($obj) and $obj->can('q_update')) {
            croak "Not a deletable object: $obj";
        }
        my ($arows, @deletes) = $obj->q_delete; # reference hand-holding
        foreach (@deletes) {
            $self->do(@$_);
        }
    }
    return 1;
}


sub qcount {
    my $self = shift;
    return $self->{sqldb_qcount};
}


sub quickrows {
    my $self = shift;
    return unless(@_);

    my @keys = $_[0]->_column_names;
    my $c = join(' ', map {'%-'.(length($_)+ 2).'.'
                           .(length($_)+ 2).'s'} @keys) . "\n";

    my $str = sprintf($c, @keys);

    foreach my $row (@_) {
        my @values = map {$row->$_} @keys;
        my @print = map {
            !defined($_) ?
            'NULL' :
            ($_ =~ m/[^[:graph:][:print:]]/ ? '*BINARY*' : $_)
        } @values;

        $str .= sprintf($c, @print);
    }
    return $str;
}
    

sub disconnect {
    my $self = shift;
    if ($self->dbh) {
        warn 'debug: Disconnecting from DBI' if($self->{sqldb_debug});
        $self->dbh->disconnect;
        delete $self->{sqldb_dbh};
    }
    return;
}


#DESTROY {
#    my $self = shift;
#    $self->disconnect;
#    return;
#}


1;
__END__

=head1 NAME

SQL::DB - Perl interface to SQL Databases

=head1 VERSION

0.17. Development release.

=head1 SYNOPSIS

  use SQL::DB qw(define_tables count max);

  define_tables(
    [
      table  => 'addresses',
      class  => 'Address',
      column => [name => 'id',   type => 'INTEGER', primary => 1],
      column => [name => 'kind', type => 'INTEGER'],
      column => [name => 'city', type => 'INTEGER'],
    ],
    [
      table  => 'persons',
      class  => 'Person',
      column => [name => 'id',      type => 'INTEGER', primary => 1],
      column => [name => 'name',    type => 'VARCHAR(255)'],
      column => [name => 'age',     type => 'INTEGER'],
      column => [name => 'address', type => 'INTEGER',
                                    ref  => 'addresses(id)',
                                    null => 1],
      column => [name => 'parent',  type => 'INTEGER',
                                    ref  => 'persons(id)',
                                    null => 1],
      index  => 'name',
    ]
  );

  my $db = SQL::DB->new();

  $db->connect('dbi:SQLite:/tmp/sqldbtest.db', 'user', 'pass', {});
  $db->deploy;

  my $persons   = $db->arow('persons');
  my $addresses = $db->arow('addresses');

  $db->do(
    insert => [$persons->id, $persons->name, $persons->age],
    values => [1, 'Homer', 43],
  );

  $db->do(
    insert => [$addresses->id, $addresses->kind, $addresses->city],
    values => [2, 'residential', 'Springfield'],  # Pg: [nextval('id')...
  );

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

=head1 DESCRIPTION

B<SQL::DB> provides a low-level interface to SQL databases, using
Perl objects and logic operators. It is NOT an Object
Relational Mapper like L<Class::DBI> and neither is it an abstraction
such as L<SQL::Abstract>. It falls somewhere inbetween.

After using define_tables() to specify your schema and creating an
B<SQL::DB> object, the typical workflow is as follows:

* connect() to the database

* deploy() the schema (CREATE TABLEs etc)

* Using one or more "abstract rows" obtained via arow() you can
do() insert, update or delete queries.

* Using one or more "abstract rows" obtained via arow() you can
fetch() (select) data to work with (and possibly modify).

* Repeat the above three steps as needed. Further queries (with a
higher level of automation) are possible with the objects returned by
fetch().

* disconnect() from the database.

B<SQL::DB> is capable of generating just about any kind of query,
including, but not limited to, JOINs, nested SELECTs, UNIONs, 
database-side operator invocations, function calls, aggregate
expressions, etc. However this package is still quite new, and nowhere
near complete. Feedback, testing, and (even better) patches are all
welcome.

For a more complete introduction see L<SQL::DB::Tutorial>.

=head1 CLASS SUBROUTINES

=head2 define_tables(@definitions)

Define the structure of tables, their columns, and associated indexes.
@definition is list of ARRAY references as required by
L<SQL::DB::Schema::Table>. This class subroutine can be called multiple
times. Will warn if you redefine a table.

=head1 METHODS

=head2 new(@names)

Create a new B<SQL::DB> object. The optional @names lists the tables
that this object is to know about. By default all tables defined by
define_tables() are known.

=head2 set_debug

Set the debugging status (true/false). With debugging turned on debug
statements are 'warn'ed.

=head2 debug

Get the debug status.

=head2 set_sqldebug

Set the SQL statement debugging status (true/false). With this turned
on all SQL statements are 'warn'ed.

=head2 sqldebug

Get the SQL debug status.

=head2 connect($dsn, $user, $pass, $attrs)

Connect to a database. The parameters are passed directly to
L<DBI>->connect. This method also informs the internal table/column
representations what type of database we are connected to, so they can
set their database-specific features accordingly. Returns the dbh.

=head2 connect_cached($dsn, $user, $pass, $attrs)

Connect to a database, potentially reusing an existing connection.  The
parameters are passed directly to L<DBI>->connect_cached. Useful when
running under persistent environments.  This method also informs the
internal table/column representations what type of database we are
connected to, so they can set their database-specific features
accordingly. Returns the dbh.

=head2 dbd

Returns the L<DBD> driver name ('SQLite', 'mysql', 'Pg' etc) for the
type of database we are connected to. Returns undef if we are not
connected.

=head2 dbh

Returns the L<DBI> database handle we are connected with.

=head2 deploy_sql

Returns a string containing the CREATE TABLE and CREATE INDEX
statements necessary to build the schema in the database. The statements
are correctly ordered based on column reference information.

=head2 create_table($name)

Creates the table and indexes in the database as previously defined by
define_tables for table $name. Will warn on any attempts to create
tables that already exist.

=head2 drop_table($name)

Drops the table and indexes in the database as previously defined by
define_tables for table $name. Will warn on any attempts to create
tables that already exist.

=head2 deploy

Creates all defined tables and indexes in the database. Will warn on
any attempts to create tables that already exist.

=head2 query(@query)

Return an L<SQL::DB::Schema::Query> object as defined by @query. This method
is useful when creating nested SELECTs, UNIONs, or you can print the
returned object if you just want to see what the SQL looks like.

=head2 query_as_string($sql, @bind_values)

An internal function for pretty printing SQL queries by inserting the
bind values into the SQL itself. Returns a string.

=head2 do(@query)

Constructs a L<SQL::DB::Schema::Query> object as defined by @query and runs
that query against the connected database.  Croaks if an error occurs.
This is the method to use for any statement that doesn't retrieve
values (eg INSERT, UPDATE and DELETE). Returns whatever value the
underlying L<DBI>->do call returns.  This method uses "prepare_cached"
to prepare the call to the database.

=head2 do_nopc(@query)

Same as for do() but uses "prepare" instead of "prepare_cached" to
prepare the call to the database. This is really only necessary if you
tend to be making recursive queries that are exactly the same.
See L<DBI> for details.

=head2 fetch(@query)

Constructs an L<SQL::DB::Schema::Query> object as defined by @query and runs
that query against the connected database.  Croaks if an error occurs.
This method should be used for SELECT-type statements that retrieve
rows. This method uses "prepare_cached" to prepare the call to the database.

When called in array context returns a list of objects based on
L<SQL::DB::Row>. The objects have accessors for each column in the
query. Be aware that this can consume large amounts of memory if there
are lots of rows retrieved.

When called in scalar context returns a query cursor (L<SQL::DB::Cursor>)
(with "next", "all" and "reset" methods) to retrieve dynamically
constructed objects one at a time.

=head2 fetch_nopc(@query)

Same as for fetch() but uses "prepare" instead of "prepare_cached" to
prepare the call to the database. This is really only necessary if you
tend to be making recursive queries that are exactly the same.
See L<DBI> for details.

=head2 fetch1(@query)

Similar to fetch() but always returns only the first object from
the result set. All other rows (if any) can not be retrieved.
You should only use this method if you know/expect one result.
This method uses "prepare_cached" to prepare the call to the database.

=head2 fetch1_nopc(@query)

Same as for fetch1() but uses "prepare" instead of "prepare_cached" to
prepare the call to the database. This is really only necessary if you
tend to be making recursive queries that are exactly the same.
See L<DBI> for details.

=head2 txn(&coderef)

Runs the code in &coderef as an SQL transaction. If &coderef does not
raise any exceptions then the transaction is commited, otherwise it is
rolled back.

Returns true/false on success/failure. The returned value can also be
printed in the event of failure. See L<Return::Value> for details.

This method can be called recursively, but any sub-transaction failure
will always result in the outer-most transaction also being rolled back.

=head2 qcount

Returns the number of successful queries that have been run.

=head2 quickrows(@objs)

Returns a string containing the column values of @objs in a tabular
format. Useful for having a quick look at what the database has returned:

    my @objs = $db->fetch(....);
    warn $db->quickrows(@objs);

=head2 create_seq($name)

This (and the seq() method below) are the only attempt that B<SQL::DB>
makes at cross-database abstraction. create_seq() creates a sequence called
$name. The sequence is actually just a row in the 'sqldb' table.

Warns if the sequence already exists, returns true if successful.

=head2 seq($name,$count)

Return the next value for the sequence $name. If $count is specified then
a list/array of $count values are returned. The uniqueness of the
returned value(s) is assured by locking the appropriate table (or rows in
the table) as required.

Note that this is not intended as a replacment for auto-incrementing primary
keys in MySQL/SQLite, or real sequences in PostgreSQL. It is simply an
ease-of-use mechanism for applications wishing to use a common sequence
api across multiple databases.

=head2 disconnect

Disconnect from the database. Effectively DBI->disconnect.

=head1 METHODS ON FETCHED OBJECTS

Although B<SQL::DB> is not an ORM system it does comes with a very
thin object layer. Objects returned by fetch() and fetch1() can be
modified using their set_* methods, just like a regular ORM system.
However, the difference here is that the objects fields may map across
multiple database tables. 

Since the objects keep track of which columns have changed, and they
also know which columns belong to which tables and which columns are
primary keys, they can also automatically generate the appropriate
commands for UPDATE or DELETE statements in order to make matching
changes in the database.

Of course, the appropriate statements only work if the primary keys have
been included as part of the fetch(). See the q_update() and q_delete()
methods in L<SQL::DB::Row> for more details.

=head2 update($sqlobject)

Nearly the same as $db->do($sqlobject->q_update).

=head2 delete($sqlobject)

Nearly the same as $db->do($sqlobject->q_delete).

=head2 insert($sqlobject)

Nearly the same as $db->do($sqlobject->q_insert).

=head1 COMPATABILITY

Version 0.13 changed the return type of the txn() method. Instead of a
2 value list indicating success/failure and error message, a single
L<Return::Value> object is returned intead.

=head1 SEE ALSO

L<SQL::Abstract>, L<DBIx::Class>, L<Class::DBI>, L<Tangram>

You can see B<SQL::DB> in action in the L<MySpam> application, also
by the same author.

=head1 AUTHOR

Mark Lawrence E<lt>nomad@null.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007,2008 Mark Lawrence <nomad@null.net>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut

# vim: set tabstop=4 expandtab:
