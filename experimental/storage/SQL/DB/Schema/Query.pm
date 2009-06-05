package SQL::DB::Schema::Query;
use strict;
use warnings;
use base qw(SQL::DB::Schema::Expr);
use Carp qw(carp croak confess);
use UNIVERSAL qw(isa);


#
# A new query - could be insert,select,update or delete
#
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    @_ || confess "usage: ". __PACKAGE__ ."->new(\@statements)";

    my $self = $proto->SUPER::new; # Get an Expr-based object
    bless($self, $class);

    $self->{is_select} = $_[0] =~ m/^select/i;

    $self->{query} = [];

    while (my $key = shift) {
        my $action = 'st_'.$key;

        unless($self->can($action)) {
            confess "Unknown command: $key. Query so far: ".
                    $self->as_string ." Next is: " .(shift).' '.(shift);
        }

        my $val    = shift;
        $self->$action($val);
    }

    $self->multi(1);
    return $self;
}


sub acolumns {
    my $self = shift;
    if ($self->{acolumns}) {
        return @{$self->{acolumns}};
    }
    return;
}


sub bind_types {
    my $self = shift;
    if ($self->{bind_types}) {
        return @{$self->{bind_types}};
    }
    return;
}


sub exists {
    my $self = shift;
    return SQL::DB::Schema::Expr->new('EXISTS ('. $self .')', $self->bind_values);
}


sub as_string {
    my $self = shift;
    my @statements = @{$self->{query}};

    my $s;
    while (my ($stm,$val) = splice(@statements,0,2)) {
        $s .= $self->$stm($val);    
    }
    unless ($self->{is_select}) {
        $s =~ s/\w+\d+\.//go;
    }
    return $s;
}


sub _alias {
    my $self = shift;
    if (!$self->{tid}) {
        $self->{tid} = $SQL::DB::Schema::ARow::tcount->{Query}++;
    }
    return 't'.$self->{tid};
}


# ------------------------------------------------------------------------
# WHERE - used in SELECT, UPDATE, DELETE
# ------------------------------------------------------------------------

sub st_where {
    my $self  = shift;
    my $where = shift;

    push(@{$self->{query}}, 'sql_where', $where);
    $self->push_bind_values($where->bind_values);
    return;
}


sub sql_where {
    my $self  = shift;
    my $where = shift;
    return "WHERE\n    " . $where . "\n";
}



# ------------------------------------------------------------------------
# INSERT
# ------------------------------------------------------------------------

sub st_insert_into {st_insert(@_)};
sub st_insert {
    my $self = shift;
    my $ref  = shift;

    $self->{bind_types} = [map {$_->_column->bind_type} @$ref];

    push(@{$self->{query}}, 'sql_insert', $ref);

    return;
}

sub sql_insert {
    my $self = shift;
    my $ref  = shift;

    return "INSERT INTO\n    ". $ref->[0]->_arow->_table_name
           . ' ('
           . join(', ', map {$_->_column->name} @{$ref})
           . ")\n";
}


sub st_values {
    my $self = shift;
    my $ref  = shift;


    push(@{$self->{query}}, 'sql_values', $ref);
    $self->push_bind_values(@{$ref});

    return;
}


sub sql_values {
    my $self = shift;
    my $ref  = shift;

    return "VALUES\n    ("
           . join(', ', map {'?'} @{$ref})
           . ")\n"
    ;
}


# ------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------

sub st_update {
    my $self = shift;
    my $ref  = shift || croak 'update requires values';

    my @items = (UNIVERSAL::isa($ref,'ARRAY') ? @$ref : $ref);
    @items || croak 'update requires values';

    foreach (@items) {
        if (UNIVERSAL::isa($_, 'SQL::DB::Schema::Expr')) {
            $self->push_bind_values($_->bind_values);
            if ($_->can('_column')) {
                push(@{$self->{bind_types}}, $_->_column->bind_type);
            }
            else {
                push(@{$self->{bind_types}}, undef);
            }
        }
    }

    push(@{$self->{query}}, 'sql_update', $items[0]->_arow->_table_name);
    push(@{$self->{query}}, 'sql_set', \@items);

    return;
}


sub sql_update {
    my $self = shift;
    my $name = shift;

    return "UPDATE\n    " . $name . "\n";
}


sub sql_set {
    my $self = shift;
    my $ref  = shift;

    return "SET\n    " . join(', ',@$ref) . "\n";
}



# ------------------------------------------------------------------------
# SELECT
# ------------------------------------------------------------------------
sub st_select {
    my $self = shift;
    my $ref  = shift;

    my @items    = ref($ref) eq 'ARRAY' ? @{$ref} : $ref;
    my @acolumns = map {UNIVERSAL::isa($_, 'SQL::DB::Schema::ARow') ? $_->_columns : $_} @items;

    $self->push_bind_values(map {UNIVERSAL::isa($_, 'SQL::DB::Schema::Expr') ? $_->bind_values : ()} @acolumns);

    push(@{$self->{acolumns}}, @acolumns);
    push(@{$self->{query}}, 'sql_select', undef);

    return;
}


sub st_distinct {
    my $self = shift;
    $self->{distinct} = shift;
    return;
}


sub st_select_distinct {
    my $self = shift;
    $self->{distinct} = 1;
    $self->st_select(@_);
    return;
}


sub sql_select {
    my $self = shift;
    my $ref  = shift;
    my $distinct = $self->{distinct};

    my $s = 'SELECT';
    if ($distinct) {
        $s .= ' DISTINCT';
        if (ref($distinct) and ref($distinct) eq 'ARRAY') {
            $s .= ' ON (' . join(', ', @{$distinct}) . ')';
        }
    }

    # The columns to select
    $s .= "\n    " .join(",\n    ", @{$self->{acolumns}});

    return $s ."\n";
}


sub st_for_update {
    my $self = shift;
    my $update = shift;
    if ($update) {
        push(@{$self->{query}}, 'sql_for_update', $update);
    }
    return;
}


sub sql_for_update {
    my $self = shift;
    my $update = shift;
    return "FOR UPDATE\n" ;
}


sub st_from {
    my $self = shift;
    my $ref  = shift;
    my @acols;

    if (UNIVERSAL::isa($ref, 'ARRAY')) {
        foreach (@{$ref}) {
            if (UNIVERSAL::isa($_, 'SQL::DB::Schema::AColumn')) {
                push(@acols, $_->_reference->_table_name .' AS '.
                             $_->_reference->_alias);
            }
            elsif (UNIVERSAL::isa($_, 'SQL::DB::Schema::ARow')) {
                push(@acols, $_->_table_name .' AS '. $_->_alias);
            }
            elsif (UNIVERSAL::isa($_, __PACKAGE__)) {
                my $str = $_->as_string;
                $str =~ s/^/    /gm;
                push(@acols, "(\n".$str.') AS '. $_->_alias);
                $self->push_bind_values($_->bind_values);
            }
            else {
                push(@acols, $_);
            }
        }
    }
    elsif (UNIVERSAL::isa($ref, 'SQL::DB::Schema::AColumn')) {
        push(@acols, $ref->_arow->_table_name .' AS '. $ref->_arow->_alias);
    }
    elsif (UNIVERSAL::isa($ref, 'SQL::DB::Schema::ARow')) {
        push(@acols, $ref->_table_name .' AS '. $ref->_alias);
    }
    elsif (UNIVERSAL::isa($ref, __PACKAGE__)) {
        my $str = $ref->as_string;
        $str =~ s/^/    /gm;
        push(@acols, "(\n".$str.') AS '. $ref->_alias);
        $self->push_bind_values($ref->bind_values);
    }
    else {
        push(@acols, $_);
    }

    push(@{$self->{query}}, 'sql_from', \@acols);
    return;
}


sub sql_from {
    my $self = shift;
    my $ref  = shift;

    return "FROM\n    ". join(",\n    ", @$ref) ."\n";
}


sub st_on {
    my $self = shift;
    my $val  = shift;
    push(@{$self->{query}}, 'sql_on', $val);
    $self->push_bind_values($val->bind_values);
    return;
}


sub sql_on {
    my $self = shift;
    my $val  = shift;
    return "ON\n    " . $val . "\n";
}


sub st_inner_join {
    my $self = shift;
    my $arow  = shift;
    push(@{$self->{query}}, 'sql_inner_join', $arow);
    return;
}


sub sql_inner_join {
    my $self = shift;
    my $arow  = shift;
    return "INNER JOIN\n    " . $arow->_table_name .' AS '. $arow->_alias . "\n";
}


sub st_left_outer_join {st_left_join(@_)};
sub st_left_join {
    my $self = shift;
    my $arow  = shift;
    UNIVERSAL::isa($arow, 'SQL::DB::Schema::ARow') || confess "join only with ARow";
    push(@{$self->{query}}, 'sql_left_join', $arow);
    return;
}


sub sql_left_join {
    my $self = shift;
    my $arow  = shift;
    return "LEFT OUTER JOIN\n    " . $arow->_table_name .' AS '. $arow->_alias . "\n";
}


sub st_right_outer_join {st_right_join(@_)};
sub st_right_join {
    my $self = shift;
    my $arow  = shift;
    push(@{$self->{query}}, 'sql_right_join', $arow);
    return;
}


sub sql_right_join {
    my $self = shift;
    my $arow  = shift;
    return "RIGHT OUTER JOIN\n    ". $arow->_table_name .' AS '. $arow->_alias ."\n";
}


sub st_full_join {
    my $self = shift;
    my $arow  = shift;
    push(@{$self->{query}}, 'sql_full_join', $arow);
    return;
}
sub st_full_outer_join {st_full_join(@_)};


sub sql_full_join {
    my $self = shift;
    my $arow  = shift;
    return "FULL OUTER JOIN\n    ". $arow->_table_name .' AS '. $arow->_alias ."\n";
}


sub st_cross_join {
    my $self = shift;
    my $arow  = shift;
    push(@{$self->{query}}, 'sql_cross_join', $arow);
    return;
}


sub sql_cross_join {
    my $self = shift;
    my $arow  = shift;
    return "CROSS JOIN\n    ". $arow->_table_name .' AS '. $arow->_alias ."\n";
}



sub st_union {
    my $self = shift;
    my $ref  = shift;
    unless(UNIVERSAL::isa($ref, 'SQL::DB::Schema::Expr')) {
        confess "Select UNION must be based on SQL::DB::Schema::Expr";
    }
    push(@{$self->{query}}, 'sql_union', $ref);
    $self->push_bind_values($ref->bind_values);
    return;
}


sub sql_union {
    my $self = shift;
    my $ref  = shift;
    return "UNION \n" . $ref . "\n";
}


sub st_intersect {
    my $self = shift;
    my $ref  = shift;
    unless(UNIVERSAL::isa($ref, 'SQL::DB::Schema::Expr')) {
        confess "Select INTERSECT must be based on SQL::DB::Schema::Expr";
    }
    push(@{$self->{query}}, 'sql_intersect', $ref);
    $self->push_bind_values($ref->bind_values);
    return;
}


sub sql_intersect {
    my $self = shift;
    my $ref  = shift;
    return "INTERSECT \n" . $ref . "\n";
}


sub st_group_by {
    my $self = shift;
    my $ref  = shift;
    push(@{$self->{query}}, 'sql_group_by', $ref);
    return;
}


sub sql_group_by {
    my $self = shift;
    my $ref  = shift;

    if (ref($ref) eq 'ARRAY') {
        return "GROUP BY\n    ".
               join(",\n    ", map {$_} @{$ref}) ."\n";
    }
    return "GROUP BY\n    " . $ref . "\n";
}


sub st_order_by {
    my $self = shift;
    my $ref  = shift;
    push(@{$self->{query}}, 'sql_order_by', $ref);
    return;
}


sub sql_order_by {
    my $self = shift;
    my $ref  = shift;

    if (ref($ref) eq 'ARRAY') {
        return "ORDER BY\n    ".
               join(",\n    ", @{$ref}) ."\n";
    }
    return "ORDER BY\n    " . $ref . "\n";
}


sub st_limit {
    my $self = shift;
    my $val  = shift;
    push(@{$self->{query}}, 'sql_limit', $val);
    return;
}


sub sql_limit {
    my $self = shift;
    my $val  = shift;
    return 'LIMIT ' . $val . "\n";
}


sub st_offset {
    my $self = shift;
    my $val  = shift;
    push(@{$self->{query}}, 'sql_offset', $val);
    return;
}


sub sql_offset {
    my $self = shift;
    my $val  = shift;
    return 'OFFSET ' . $val . "\n";
}



# ------------------------------------------------------------------------
# DELETE
# ------------------------------------------------------------------------

sub st_delete {
    my $self = shift;
    my $arow = shift;
    UNIVERSAL::isa($arow, 'SQL::DB::Schema::ARow') ||
        confess "Can only delete type SQL::DB::Schema::ARow";
    push(@{$self->{query}}, 'sql_delete', $arow);
    return;
}
sub st_delete_from {st_delete(@_)};


sub sql_delete {
    my $self = shift;
    my $arow = shift;
    return "DELETE FROM\n    ". $arow->_table->name ."\n"; 
}


1;


__END__
# vim: set tabstop=4 expandtab:


=head1 NAME

SQL::DB::Schema::Query - description

=head1 SYNOPSIS

  use SQL::DB::Schema::Query;

=head1 DESCRIPTION

B<SQL::DB::Schema::Query> is ...

=head1 METHODS

=head2 new



=head2 push_bind_values




=head2 acolumns

Only valid for select type queries.

=head2 bind_types

Only valid for !select type queries.


=head2 exists



=head2 as_string



=head2 st_where



=head2 sql_where



=head2 st_insert_into



=head2 st_insert



=head2 sql_insert



=head2 st_values



=head2 sql_values



=head2 st_update



=head2 sql_update



=head2 sql_set



=head2 st_select




=head2 sql_select


=head2 st_select_distinct

=head2 st_distinct



=head2 st_for_update



=head2 sql_for_update



=head2 st_from



=head2 sql_from



=head2 st_on



=head2 sql_on



=head2 st_inner_join



=head2 sql_inner_join



=head2 st_left_outer_join



=head2 st_left_join



=head2 sql_left_join



=head2 st_right_outer_join



=head2 st_right_join



=head2 sql_right_join



=head2 st_full_join



=head2 st_full_outer_join



=head2 sql_full_join



=head2 st_cross_join



=head2 sql_cross_join



=head2 st_union



=head2 sql_union



=head2 st_intersect



=head2 sql_intersect



=head2 st_group_by



=head2 sql_group_by



=head2 st_order_by



=head2 sql_order_by



=head2 st_limit



=head2 sql_limit



=head2 st_offset



=head2 sql_offset



=head2 st_delete



=head2 st_delete_from



=head2 sql_delete



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
