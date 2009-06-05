package SQL::DB::Schema::Table;
use strict;
use warnings;
use Carp qw(carp croak confess);
use Scalar::Util qw(weaken);
use SQL::DB::Schema::Column;
use SQL::DB::Row;
use SQL::DB::Schema::ARow;

our $DEBUG;

my @reserved = qw(
    sql
    sql_index
    asc
    desc
    is_null
    not_null
    is_not_null
    exists
); 


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {
        columns => [],
        db_type => '',
    };
    bless($self, $class);

    while (my ($key,$val) = splice(@_, 0, 2)) {
        my $action = 'setup_'.$key;
        if (!$self->can($action)) {
            warn "Unknown Table definition: $key";
            next;
        }

        if (ref($val) and ref($val) eq 'ARRAY') {
            $self->$action(@{$val});
        }
        else {
            $self->$action($val);
        }
    }

    # Abstract class setup
    no strict 'refs';
    my $aclass = 'SQL::DB::Schema::ARow::'. $self->{name};
    my $isa = \@{$aclass . '::ISA'};
    if (defined @{$isa}) {
        carp "redefining $aclass";
    }
    push(@{$isa}, 'SQL::DB::Schema::ARow');
    $aclass->mk_accessors($self->column_names_ordered);
    {
        no warnings 'once';
        ${$aclass .'::TABLE'} = $self;
    }

    foreach my $colname ($self->column_names_ordered) {
        *{$aclass .'::set_'. $colname} = sub {
            my $self = shift;
            return $self->$colname->set(@_);
        };
    }

    if (my $class = $self->{class}) {
        my $isa = \@{$class . '::ISA'};
        if (defined @{$isa}) {
            carp "redefining $class";
        }

        my $baseclass = SQL::DB::Row->make_class_from($self->columns);
        push(@{$isa}, $baseclass);
    }

    return $self;
}


sub setup_schema {
    my $self = shift;
    $self->{schema} = shift;
    weaken($self->{schema});
    return;
}

# DR
sub setup_db {
    my $self = shift;
    $self->{db} = shift;
}


sub setup_table {
    my $self      = shift;
    $self->{name} = shift;
    if ($self->{name} !~ m/[a-z_]/) {
        warn "Table '$self->{name}' is not all lowercase";
    }

}


sub setup_class {
    my $self       = shift;
    $self->{class} = shift;
}


sub setup_bases {
    my $self       = shift;
    foreach my $class (@_) {
        if (!eval "require $class;1;") {
            die "Base Class $class could not be loaded: $@";
        }
    }
    $self->{bases} = [@_];
}


sub setup_column {
    my $self = shift;

    my $col = SQL::DB::Schema::Column->new();
    $col->table($self);

    while (my $key = shift) {
        if ($key eq 'name') {
            my $val = shift;
            if (grep(m/^$val$/, @reserved)) {
                croak "Column can't be called '$val': reserved name";
            }

            if (exists($self->{column_names}->{$val})) {
                croak "Column $val already defined for table $self->{name}";
            }
            $col->name($val);
        }
        else {
            $col->$key(shift);
        }
    }
    $col->name || confess 'Column in table '.$self.' missing name';
    push(@{$self->{columns}}, $col);
    $self->{column_names}->{$col->name} = $col;
    push(@{$self->{column_names_ordered}},$col->name);
}


sub setup_columns {
    my $self = shift;

    foreach my $array (@_) {
        $self->setup_column(@$array);
    }
}


sub setup_primary {
    my $self = shift;
    my $def  = shift;
    push(@{$self->{primary}}, $self->text2cols($def));
}


sub add_primary {
    my $self = shift;
    push(@{$self->{primary}}, @_);
}


sub setup_unique {
    my $self = shift;
    my $def  = shift;
    push(@{$self->{unique}}, [$self->text2cols($def)]);
}


sub setup_unique_index {
    my $self = shift;
    my $hashref = {unique => 1};

    while (my $def = shift) {
        my $val = shift;
        if ($val) {
            if ($def eq 'columns' and ref($val) and ref($val) eq 'ARRAY') {
                foreach my $col (@{$val}) {
                    (my $c = $col) =~ s/\s.*//;
                if (!exists($self->{column_names}->{$c})) {
                        confess "Index column $c not in table $self->{name}";
                    }
                }
            }
            elsif ($def eq 'columns') {
                my @vals;
                foreach my $col (split(m/,\s*/, $val)) {
                    (my $c = $col) =~ s/\s.*//;
                    if (!exists($self->{column_names}->{$c})) {
                        confess "Index column $c not in table $self->{name}";
                    }
                    push(@vals, $col);
                }
                $val = \@vals;
            }
            $hashref->{$def} = $val;
        }
        else {
            my @vals;
            foreach my $col (split(m/,\s*/, $def)) {
                (my $c = $col) =~ s/\s.*//;
                    if (!exists($self->{column_names}->{$c})) {
                    confess "Index column $c not in table $self->{name}";
                }
                push(@vals, $col);
            }
            $hashref->{columns} = \@vals;
        }
    }
    push(@{$self->{index}}, $hashref);
}


sub setup_index {
    my $self = shift;
    my $hashref = {};

    while (my $def = shift) {
        my $val = shift;
        if ($val) {
            if ($def eq 'columns' and ref($val) and ref($val) eq 'ARRAY') {
                foreach my $col (@{$val}) {
                    (my $c = $col) =~ s/\s.*//;
                if (!exists($self->{column_names}->{$c})) {
                        confess "Index column $c not in table $self->{name}";
                    }
                }
            }
            elsif ($def eq 'columns') {
                my @vals;
                foreach my $col (split(m/,\s*/, $val)) {
                    (my $c = $col) =~ s/\s.*//;
                    if (!exists($self->{column_names}->{$c})) {
                        confess "Index column $c not in table $self->{name}";
                    }
                    push(@vals, $col);
                }
                $val = \@vals;
            }
            $hashref->{$def} = $val;
        }
        else {
            my @vals;
            foreach my $col (split(m/,\s*/, $def)) {
                (my $c = $col) =~ s/\s.*//;
                    if (!exists($self->{column_names}->{$c})) {
                    confess "Index column $c not in table $self->{name}";
                }
                push(@vals, $col);
            }
            $hashref->{columns} = \@vals;
        }
    }
    push(@{$self->{index}}, $hashref);
}


sub setup_foreign {
    my $self = shift;
    warn 'multi foreign not implemented yet';
}


sub setup_type_mysql {
    my $self = shift;
    $self->{engine_mysql} = shift;
}


sub setup_engine_mysql {
    my $self = shift;
    $self->{engine_mysql} = shift;
}


sub setup_default_charset_mysql {
    my $self = shift;
    $self->{default_charset_mysql} = shift;
}


sub setup_default_charset_pg {
    my $self = shift;
    $self->{default_charset_pg} = shift;
}


sub setup_tablespace_pg {
    my $self = shift;
    $self->{tablespace_pg} = shift;
}


sub text2cols {
    my $self = shift;
    my $text = shift;
    my @cols = ();

    if (ref($text) and ref($text) eq 'ARRAY') {
        return map {$self->text2cols($_)} @{$text};
    }

    if (ref($text)) {
        confess "text2cols called with non-scalar and non-arrayref: $text";
    }

    if ($text =~ /\s*(.*)\s*\((.*)\)/) {
        my $table;
        unless (eval {$table = $self->{schema}->table($1);1;}) {
            confess "Table $self->{name}: Foreign table $1 not yet defined.\n".
                  "Known tables: " 
                    . join(',', map {$_->name} $self->{schema}->tables);
        }
        foreach my $column_name (split(/,\s*/, $2)) {
            unless($table->column($column_name)) {
                confess "Table $self->{name}: Foreign table '$1' has no "
                     ."column '$column_name'";
            }
            push(@cols, $table->column($column_name));
        }
    }
    else {
        foreach my $column_name (split(/,\s*/, $text)) {
            unless(exists($self->{column_names}->{$column_name})) {
                confess "Table $self->{name}: No such column '$column_name'";
            }
            push(@cols, $self->{column_names}->{$column_name});
        }
    }
    if (!@cols) {
        confess 'No columns found in text: '. $text;
    }
    return @cols;
}

# DR
sub db {
    my $self = shift;
    return $self->{db};
}

sub name {
    my $self = shift;

    return $self->db
        ? $self->db . '.' . $self->{name}
        : $self->{name};

    return $self->{name};
}


sub class {
    my $self = shift;
    return $self->{class};
}


sub columns {
    my $self = shift;
    return @{$self->{columns}};
}


sub column_names {
    my $self = shift;
    return sort keys %{$self->{column_names}};
}


sub column_names_ordered {
    my $self = shift;
    return @{$self->{column_names_ordered}};
}


sub column {
    my $self = shift;
    my $name = shift;
    if (!exists($self->{column_names}->{$name})) {
        return;
    }
    return $self->{column_names}->{$name};
}


sub primary_columns {
    my $self = shift;
    return @{$self->{primary}} if($self->{primary});
    return;
}


sub primary_column_names {
    my $self = shift;
    return map {$_->name} @{$self->{primary}} if($self->{primary});
    return;
}


sub arow {
    my $self   = shift;
    my $class  = 'SQL::DB::Schema::ARow::' . $self->name;
    return $class->new;
}


sub schema {
    my $self = shift;
    return $self->{schema};
}


sub set_db_type {
    my $self = shift;
    $self->{db_type} = shift || confess 'usage: set_db_type($type)';
}


sub db_type {
    my $self = shift;
    return $self->{db_type} || '';
}


sub sql_primary {
    my $self = shift;
    if (!$self->{primary}) {
        return '';
    }
    return 'PRIMARY KEY('
           . join(', ', map {$_->name} @{$self->{primary}}) .')';
}


sub sql_unique {
    my $self = shift;

    if (!$self->{unique}) {
        return ();
    }

    my @sql = ();

    # a list of arrays
    foreach my $u (@{$self->{unique}}) {
        push(@sql, 'UNIQUE ('
                . join(', ', map {$_->name} @{$u})
                . ')'
        );
    }

    return @sql;
}


sub sql_foreign {
    my $self = shift;
    if (!$self->{foreign}) {
        return '';
    }
    my $sql = '';
    foreach my $f (@{$self->{foreign}}) {
        my @cols = @{$f->{columns}};
        my @refs = @{$f->{references}};
        $sql .= 'FOREIGN KEY ('
                . join(', ', @cols)
                . ') REFERENCES ' . $refs[0]->table->{name} .' ('
                . join(', ', @refs)
                . ')'
        ;
    }
    return $sql;
}


sub sql_engine_mysql {
    my $self = shift;
    unless ($self->{db_type} eq 'mysql' and $self->{engine_mysql}) {
        return '';
    }
    return ' ENGINE='.$self->{engine_mysql};
}


sub sql_default_charset_mysql {
    my $self = shift;
    unless ($self->{db_type} eq 'mysql' and $self->{default_charset_mysql}) {
        return '';
    }
    return ' DEFAULT CHARACTER SET '.$self->{default_charset_mysql};
}


sub sql_default_charset_pg {
    my $self = shift;
    unless ($self->{db_type} eq 'pg' and $self->{default_charset_pg}) {
        return '';
    }
    return ' DEFAULT_CHARSET='.$self->{default_charset_pg};
}


sub sql_create_table {
    my $self = shift;
    my @vals = map {$_->sql} $self->columns;
    push(@vals, $self->sql_primary) if ($self->{primary});
    push(@vals, $self->sql_unique) if ($self->{unique});
    push(@vals, $self->sql_foreign) if ($self->{foreign});

    return 'CREATE TABLE '
           . $self->name
           . " (\n    " . join(",\n    ", @vals) . "\n)"
           . $self->sql_engine_mysql
           . $self->sql_default_charset_mysql
           . $self->sql_default_charset_pg
    ;
}

sub sql_create_indexes {
    my $self = shift;
    my @sql = ();

    foreach my $index (@{$self->{index}}) {
        my @cols = @{$index->{columns}};
        my @colsflat;
        foreach (@cols) {
            (my $x = $_) =~ s/\s/_/g;
            push(@colsflat, $x);
        }
        push(@sql, 'CREATE'
                . ($index->{unique} ? ' UNIQUE' : '')
                . ' INDEX '
                . join('_',$self->name, @colsflat)
                . ' ON ' . $self->{name}
                . ($index->{using} ? ' USING '.$index->{using} : '')
                . ' (' . join(',', @cols) . ')'
        );
    }
    return @sql;
}


sub sql_create {
    my $self = shift;
    return ($self->sql_create_table, $self->sql_create_indexes);
}


DESTROY {
    my $self = shift;
    warn 'DESTROY Table '.$self->name if($DEBUG and $DEBUG>2);
}


1;
__END__

=head1 NAME

SQL::DB::Schema::Table - Perl representation of an SQL database table

=head1 SYNOPSIS

  use SQL::DB::Schema::Table;

  my $table = SQL::DB::Schema::Table->new(
      table   => 'users',
      class   => 'User',
      columns => [
           [name => 'id',  type => 'INT',          primary => 1],
           [name => 'name',type => 'VARCHAR(255)', unique  => 1],
      ],
      index => [
        columns => 'name',
        type    => 'BTREE',
      ],
  );

  print $table->sql;

  #

=head1 DESCRIPTION

B<SQL::DB::Schema::Table> objects represent SQL database tables. Once
defined, a B<SQL::DB::Schema::Table> object can be queried for information
about the table such as the primary keys, name and type of the
columns, and the SQL table creation syntax.

=head1 DEFINITION KEYS

Key/value pairs can be set multiple times, for example when there is
more than one index in the table.

=head2 schema => $schema

$schema must be a L<SQL::DB::Schema> object. The internal reference to
the schema is set to be weak.

=head2 table => $name

$name is the SQL name of the table.

=head2 class => $name

$name is the Perl class to be created for representing table rows.

=head2 bases => [$class1, $class2,...]

A list of classes that the class will inherit from.

=head2 columns => [ $col1, $col2, ... ]

$col1, $col2, ... are passed directly to L<SQL::DB::Schema::Column> new().

=head2 primary => [ $name1, $name2, ... ]

$name1, $name2, ... are the columns names which are primary.
Should only be used if the table has a multiple-column primary key.
If the table has only a single primary key then that should be set
in the column definition.

=head2 unique => [ $name1, $name2, ... ]

$name1, $name2, ... are columns names which must be unique.
Should only be used if the table has a multiple-column unique requirements,
Note that column definitions can also include unique requirements.
This key can be defined more than once with a culmative result.

=head2 index => $def

$def is an array reference of the following form. Note that not all
databases accept all definitions.

  [ columns => 'col1,col2', type => $type ]

=head2 foreign

For multiple foreign key definition. Not presently implemented.

=head2 type => $type

$type specifies the SQL table type. Applies only to PostgreSQL.

=head2 engine => $engine

$engine specifies the SQL backend engine. Applies only to MySQL.

=head2 default_charset => $charset

$charset specifies the SQL default character set. Applies only to MySQL.

=head2 tablespace => $tspace

$tspace specifies the PostgreSQL tablespace definition.

=head1 METHODS

=head2 new(@definition)

Returns a new B<SQL::DB::Schema::Table> object. The @definition is a list
of key/value pairs as defined under L<DEFINITION KEYS>.

=head2 name

Returns the SQL name of the database table.

=head2 class

Returns the name of the Perl class which can represent rows in the
table.

=head2 columns

Returns the list of L<SQL::DB::Schema::Column> objects representing each column
definition in the database. The order is the same as they were defined.

=head2 column($name)

Returns the L<SQL::DB::Schema::Column> object for the column $name.

=head2 column_names

Returns a list of the SQL names of the columns.

=head2 primary_columns

Returns the list of L<SQL::DB::Schema::Column> objects which have been defined
as primary.

=head2 primary_column_names

Returns the list of columns names which have been defined as primary.

=head2 schema

Returns the schema (a L<SQL::DB::Schema> object) which this table
is a part of.

=head2 sql

Returns the SQL statement for table creation.

=head2 sql_index

Returns the list of SQL statements for table index creation.

=head1 INTERNAL METHODS

These are used internally but are documented here for completeness.

=head2 add_primary

=head2 text2cols

=head1 SEE ALSO

L<SQL::DB::Schema>, L<SQL::DB::Schema::Column>, L<SQL::DB>

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


=head1 NAME

SQL::DB::Schema::Table - description

=head1 SYNOPSIS

  use SQL::DB::Schema::Table;

=head1 DESCRIPTION

B<SQL::DB::Schema::Table> is ...

=head1 METHODS

=head2 new



=head2 setup_schema



=head2 setup_table



=head2 setup_class



=head2 setup_bases



=head2 setup_column



=head2 setup_columns



=head2 setup_primary



=head2 add_primary



=head2 setup_unique



=head2 setup_unique_index



=head2 setup_index



=head2 setup_foreign



=head2 setup_default_charset_mysql
=head2 setup_default_charset_pg
=head2 setup_engine_mysql
=head2 setup_tablespace_pg
=head2 setup_type_mysql


=head2 text2cols



=head2 name



=head2 class



=head2 columns



=head2 column_names



=head2 column_names_ordered



=head2 column



=head2 primary_columns



=head2 primary_column_names



=head2 arow



=head2 schema


=head2 set_db_type


=head2 db_type



=head2 sql_primary



=head2 sql_unique



=head2 sql_foreign




=head2 sql_default_charset_mysql
=head2 sql_default_charset_pg
=head2 sql_engine_mysql



=head2 sql_create_table



=head2 sql_create_indexes



=head2 sql_create



=head1 FILES



=head1 SEE ALSO

L<Other>

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
