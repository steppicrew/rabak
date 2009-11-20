package SQL::DB::Schema::Column;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use Carp qw(carp croak);
use Scalar::Util qw(weaken);

SQL::DB::Schema::Column->mk_accessors(qw(
    table
    name
    null
    default
    unique
    auto_increment
));


our $DEBUG;


sub table {
    my $self = shift;
    if ( @_ ) {
        my $table = shift;
        unless(CORE::ref($table) and CORE::ref($table) eq 'SQL::DB::Schema::Table') {
            croak "table must be a SQL::DB::Schema::Table";
        }
        $self->{table} = $table;
        weaken($self->{table});
    }
    return $self->{table};
}


sub primary {
    my $self = shift;
    if (@_) {
        if ($self->{primary} = shift) {
            $self->{table}->add_primary($self);
        }
    }
    else {
        return $self->{primary};
    }
}


sub type {
    my $self = shift;
    if (@_) {
        $self->{type} = shift;
        return;
    }
    if (!$self->{table}) {
        return $self->{type};
    }

    my $type = 'type_' . $self->{table}->db_type;
    if (exists($self->{$type}) and $self->{$type}) {
        return $self->{$type};
    }
    return $self->{type};
}


sub type_Pg {
    my $self = shift;
    if (@_) {
        $self->{type_Pg} = shift;
        return;
    }
    croak 'usage: type_Pg($type)';
}


sub type_mysql {
    my $self = shift;
    if (@_) {
        $self->{type_mysql} = shift;
        return;
    }
    croak 'usage: type_mysql($type)';
}


sub bind_type {
    my $self = shift;
    if (@_) {
        $self->{bind_type} = shift;
        return;
    }
    if (!$self->{table}) {
        return $self->{bind_type};
    }

    my $type = 'bind_type_' . $self->{table}->db_type;
    if (exists($self->{$type}) and $self->{$type}) {
        return $self->{$type};
    }
    return $self->{bind_type};
}


sub bind_type_Pg {
    my $self = shift;
    if (@_) {
        $self->{bind_type_Pg} = shift;
        return;
    }
    croak 'usage: bind_type_Pg($type)';
}


sub bind_type_mysql {
    my $self = shift;
    if (@_) {
        $self->{bind_type_mysql} = shift;
        return;
    }
    croak 'usage: bind_type_mysql($type)';
}


#
# This is a delayed value function. Takes a string, but first time
# is accessed it finds the real column and sets itself to that column.
#
sub ref {references(@_);};
sub references {
    my $self = shift;
    # Set a value
    if (@_) {
        $self->{references} = shift;
        return;
    }

    # Not set
    if (!$self->{references}) {
        return;
    }

    # Already accessed - return the reference to SQL::DB::Schema::Column
    if (CORE::ref($self->{references})) {
        return $self->{references};
    }

    # Not yet accessed - find the reference to SQL::DB::Schema::Column
    my @cols = $self->table->text2cols($self->{references});
    $self->{references} = $cols[0];
    weaken($self->{references});
#   $col->table->has_many($self);
    return $self->{references};
}


sub deferrable {
    my $self = shift;

    if (@_) {
        $self->{deferrable} = uc(shift);
    }
    return $self->{deferrable} if(exists($self->{deferrable}));
    return;
}


sub set {
    my $self = shift;

    if (@_) {
        my $sub = shift;
        (CORE::ref($sub) && CORE::ref($sub) eq 'CODE') ||
            croak 'set requires a CODEREF argument';
        $self->{set} = $sub;
    }

    return $self->{set};
}


sub inflate {
    my $self = shift;

    if (@_) {
        my $sub  = shift || croak 'inflate requires a CODEREF argument';
        (CORE::ref($sub) && CORE::ref($sub) eq 'CODE') ||
            croak 'inflate requires a CODEREF argument';
        $self->{inflate} = $sub;
    }
    return $self->{inflate};
}


sub deflate {
    my $self = shift;

    if (@_) {
        my $sub  = shift || croak 'deflate requires a CODEREF argument';
        (CORE::ref($sub) && CORE::ref($sub) eq 'CODE') ||
            croak 'deflate requires a CODEREF argument';
        $self->{deflate} = $sub;
    }
    return $self->{deflate};
}


sub sql_default {
    my $self = shift;
    my $default = $self->default;
    if (!defined($default)) {
        return '';
    }
    if (CORE::ref($default) and CORE::ref($default) eq 'CODE') {
        return '';
    }

    if ($self->type =~ m/(int)|(real)|(float)|(double)|(numeric)/i) {
        return ' DEFAULT ' . $default
    }
    return " DEFAULT '" . $default ."'";
}


sub sql {
    my $self = shift;
    my $def = '';
    if (exists($self->{deferrable})) {
        if ($self->{deferrable}) {
            $def = ' DEFERRABLE '.$self->{deferrable};
        }
        else {
            $def = ' NOT DEFERRABLE';
        }
    }

    return sprintf('%-15s %-15s', $self->name, $self->type)
           . ($self->null ? 'NULL' : 'NOT NULL')
           . $self->sql_default
           . ($self->auto_increment ? ' AUTO_INCREMENT' : '')
           . ($self->unique ? ' UNIQUE' : '')
#           . ($self->primary ? ' PRIMARY KEY' : '')
           . ($self->references ? 
                (' REFERENCES ' . $self->references->table->{name} .'('
                 . $self->references->name .')'. $def  
                ) : ''
             )
    ;
}


DESTROY {
    my $self = shift;
    warn "DESTROY $self" if($DEBUG);
}

1;
__END__
# vim: set tabstop=4 expandtab:


=head1 NAME

SQL::DB::Schema::Column - description

=head1 SYNOPSIS

  use SQL::DB::Schema::Column;

=head1 DESCRIPTION

B<SQL::DB::Schema::Column> is ...

=head1 METHODS

=head2 table


=head2 name


=head2 null


=head2 default


=head2 unique


=head2 auto_increment



=head2 primary

=head2 type
=head2 type_Pg
=head2 type_mysql


=head2 bind_type
=head2 bind_type_Pg
=head2 bind_type_mysql


=head2 ref



=head2 references

=head2 deferrable


=head2 set

Takes an object method (subroutine reference) which is run when
SQL::DB::Row->set_column($val) is called. The subref has access to the
row object and all of its columns, but must return the value for the
column and not set it.


=head2 inflate



=head2 deflate



=head2 sql_default



=head2 sql



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
