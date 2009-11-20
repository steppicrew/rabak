package SQL::DB::Schema::AColumn;
use strict;
use warnings;
use base qw(SQL::DB::Schema::Expr);
use Carp qw(carp croak confess);
use Scalar::Util qw(weaken);
use UNIVERSAL qw(isa);


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new;

    my $col   = shift;
    my $arow  = shift;
    $self->{col}  = $col;  # column definition SQL::DB::Schema::AColumn
    $self->{arow} = $arow; # abstract representation of a table row
    weaken($self->{arow});

    $self->{expr_as}   = $col->name; #FIXME shouldn't know about Expr internals
    $self->set_val($arow->_alias .'.'. $col->name);


    bless($self, $class);
    return $self;
}


sub _column {
    my $self = shift;
    return $self->{col};
}


sub _arow {
    my $self = shift;
    return $self->{arow};
}


sub expr_not {is_null(@_);}
sub is_null {
    my $self     = shift;
    $self        = $self->_clone();
    $self->set_val($self->{arow}->_alias .'.'. $self->{col}->name .' IS NULL');
    return $self;
}


sub is_not_null {
    my $self     = shift;
    $self        = $self->_clone();
    $self->set_val($self->{arow}->_alias .'.'. $self->{col}->name 
                   .' IS NOT NULL');
    return $self;
}


sub like {
    my $self     = shift;
    my $like     = shift || croak 'like() requires an argument';
    $self        = $self->_clone();
    $self->set_val($self->{arow}->_alias .'.'. $self->{col}->name .' LIKE ?');
    $self->push_bind_values($like);
    return $self;
}


sub asc {
    my $self     = shift;
    $self        = $self->_clone();
    $self->set_val($self->{arow}->_alias .'.'. $self->{col}->name .' ASC');
    return $self;
}


sub desc {
    my $self     = shift;
    $self        = $self->_clone();
    $self->set_val($self->{arow}->_alias .'.'. $self->{col}->name .' DESC');
    return $self;
}


sub set {
    my $self     = shift;
    @_ || confess 'set() requires an argument:'. $self;
    my $val      = shift;
    $self        = $self->_clone();
    if (UNIVERSAL::isa($val, 'SQL::DB::Schema::Expr')) {
        $self->set_val($self->{col}->name .' = '. $val);
        $self->push_bind_values($val->bind_values);
    }
    else {
        $self->set_val($self->{col}->name .' = ?');
        $self->push_bind_values($val);
    }
    return $self;
}


DESTROY {
    my $self = shift;
    warn "DESTROY $self" if($SQL::DB::DEBUG && $SQL::DB::DEBUG>3);
}


1;
__END__
# vim: set tabstop=4 expandtab:


=head1 NAME

SQL::DB::Schema::AColumn - description

=head1 SYNOPSIS

  use SQL::DB::Schema::AColumn;

=head1 DESCRIPTION

B<SQL::DB::Schema::AColumn> is ...

=head1 METHODS

=head2 new



=head2 _column



=head2 _arow



=head2 is_null



=head2 is_not_null

SQL: IS NOT NULL


=head2 expr_not



=head2 like



=head2 asc



=head2 desc



=head2 set



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
