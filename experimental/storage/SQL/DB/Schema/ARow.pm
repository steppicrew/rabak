package SQL::DB::Schema::ARow;
use strict;
use warnings;
use base qw(Class::Accessor);
use Carp qw(carp croak confess cluck);
use SQL::DB::Schema::AColumn;
use Scalar::Util qw(weaken);


our $DEBUG;


our $tcount = {};


sub _getid {
    my $name = shift;
    $tcount->{$name} ||= [];
    my $i = 0;
    while ($tcount->{$name}->[$i]) {
        $i++;
    }
    $tcount->{$name}->[$i] = 1;
    return $i;
}


sub _releaseid {
    my ($name,$i) = @_;
    $tcount->{$name}->[$i] = undef;
    return;
}


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless($self, $class);

    $self->{arow_tid} = _getid($self->_table->name);

    foreach my $col ($self->_table->columns) {
        my $acol = SQL::DB::Schema::AColumn->new($col, $self);

        push(@{$self->{arow_columns}}, $acol);
        $self->{arow_column_names}->{$col->name} = $acol;
        $self->{$col->name} = $acol;
    }
    return $self;
}


sub _table {
    my $self = shift;
    no strict 'refs';
    return ${(ref($self) || $self) . '::TABLE'};
}


sub _table_name {
    my $self = shift;
    return $self->_table->name;

    return $self->_table->db
        ? $self->_table->db . '.' . $self->_table->name
        : $self->_table->name;
}


sub _alias {
    my $self = shift;
    return $self->_table->name . ($self->{arow_tid}+1);
}


sub _columns {
    my $self = shift;
    return @{$self->{arow_columns}};
}


sub _column_names {
    my $self = shift;
    return $self->_table->column_names_ordered;
}


DESTROY {
    my $self = shift;
    _releaseid($self->_table->name, $self->{arow_tid});
    warn "DESTROY $self" if($SQL::DB::DEBUG && $SQL::DB::DEBUG>3);
}

1;
__END__
# vim: set tabstop=4 expandtab:


=head1 NAME

SQL::DB::Schema::ARow - description

=head1 SYNOPSIS

  use SQL::DB::Schema::ARow;

=head1 DESCRIPTION

B<SQL::DB::Schema::ARow> is ...

=head1 METHODS

=head2 new



=head2 _table



=head2 _table_name



=head2 _alias



=head2 _columns



=head2 _column_names



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
