package SQL::DB::Schema::Expr;
use strict;
use warnings;
use Carp;
use UNIVERSAL qw(isa);
use overload
    'eq'     => 'expr_eq',
    '=='     => 'expr_eq',
    '!='     => 'expr_ne',
    'ne'     => 'expr_ne',
    '&'      => 'expr_and',
    '!'      => 'expr_not',
    '|'      => 'expr_or',
    '<'      => 'expr_lt',
    '>'      => 'expr_gt',
    '<='     => 'expr_lte',
    '>='     => 'expr_gte',
    '+'      => 'expr_plus',
    '-'      => 'expr_minus',
    '*'      => 'expr_multiply',
    '/'      => 'expr_divide',
    '""'     => 'as_string',
    fallback => 1,
;


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
        expr_val         => shift,
        expr_op          => '',
        expr_multi       => 0,
        expr_bind_values => \@_,
    };
    bless($self, $class);

    # This is due to some wierdness in Perl - seems to call new() twice.
    if (isa($self->{expr_val}, __PACKAGE__)) {
        return $self->{expr_val};
    }

    return $self;
}


sub _clone {
    my $self  = shift;
    my $class = ref($self) || croak 'can only _clone blessed objects';
    my $new   = {};
    map {$new->{$_} = $self->{$_}} keys %$self;
    bless($new, $class);
    $new->reset_bind_values();
    return $new;
}


sub as {
    my $self        = shift;
    my $new         = $self->_clone();
    $new->{expr_as} = shift || croak 'as() requires an argument';
    $new->push_bind_values($self->bind_values);
    if ($self->op) {
        $new->set_val('('.$self->val .') AS '. $new->{expr_as});
    }
    else {
        $new->set_val($self->val .' AS '. $new->{expr_as});
    }
    return $new;
}


sub _as {
    my $self = shift;
    return $self->{expr_as};
}


sub val {
    my $self = shift;
    return $self->{expr_val};
}


sub set_val {
    my $self = shift;
    if (@_) {
        $self->{expr_val} = shift;
        return;
    }
    croak 'set_val requires an argument';
}


sub reset_bind_values {
    my $self = shift;
    $self->{expr_bind_values} = [];
}


sub push_bind_values {
    my $self = shift;
    push(@{$self->{expr_bind_values}}, @_);
}


sub bind_values {
    my $self = shift;
    return @{$self->{expr_bind_values}};
}


sub multi {
    my $self = shift;
    $self->{expr_multi} = shift if(@_);
    return $self->{expr_multi};
}


sub op {
    my $self = shift;
    $self->{expr_op} = shift if(@_);
    return $self->{expr_op};
}


sub as_string {
    my $self = shift;
    if ($self->{expr_multi}) {
        return '(' . $self->{expr_val} .')';
    }
    return $self->{expr_val};
}


sub bind_values_sql {
    my $self = shift;
    if (my @vals = $self->bind_values) {
        return '/* ('
           . join(", ", map {defined $_ ? "'$_'" : 'NULL'} @vals)
           . ') */';
    }
    return '';
}


sub _as_string {
    my $self = shift;
    my @values = $self->bind_values;
    return $self->as_string . $self->bind_values_sql . "\n";
}



sub expr_binary {
    my ($e1,$op,$e2) = @_;
    my @bind = ();

    if (isa($e1, __PACKAGE__)) {
        push(@bind, $e1->bind_values);
        if ($e1->multi
            or ($op =~ /^OR/ and $e1->op =~ /^(OR)|(AND)/)
            or ($op =~ /^AND/ and $e1->op =~ /^OR/)) {
            # always return a new expression, because if we set multi
            # on the current object we screw it up when it is used in
            # other queries.
            $e1 = __PACKAGE__->new("$e1", $e1->bind_values);
            $e1->multi(1);
        }
    }
    else {
        push(@bind, $e1);
        $e1 = '?';
    }

    if (isa($e2, __PACKAGE__)) {
        push(@bind, $e2->bind_values);
        if ($e2->multi
            or ($op =~ /^OR/ and $e2->op =~ /^(OR)|(AND)/)
            or ($op =~ /^AND/ and $e2->op =~ /^OR/)) {
            # same as above
            $e2 = __PACKAGE__->new("$e2", $e2->bind_values);
            $e2->multi(1);
        }
    }
    else {
        push(@bind, $e2);
        $e2 = '?';
    }

    my $expr = __PACKAGE__->new($e1.' '.$op.' '.$e2, @bind);
    $expr->op($op);
    return $expr;
}

sub expr_eq {
    return expr_binary($_[0],'=',$_[1]);
}

sub expr_ne {
    return expr_binary($_[0],'!=',$_[1]);
}

sub expr_and {
    return expr_binary($_[0],'AND',$_[1]);
}

sub expr_or {
    return expr_binary($_[0],'OR',$_[1]);
}

sub and {
    return expr_binary($_[0],'AND',$_[1]);
}

sub or {
    return expr_binary($_[0],'OR',$_[1]);
}

sub and_not {
    return expr_binary($_[0],'AND NOT',$_[1]);
}

sub or_not {
    return expr_binary($_[0],'OR NOT',$_[1]);
}

sub expr_lt {
    if ($_[2]) {
        return expr_binary($_[1],'<',$_[0]);
    }
    else {
        return expr_binary($_[0],'<',$_[1]);
    }
}

sub expr_lte {
    if ($_[2]) {
        return expr_binary($_[1],'<=',$_[0]);
    }
    else {
        return expr_binary($_[0],'<=',$_[1]);
    }
}

sub expr_gt {
    if ($_[2]) {
        return expr_binary($_[1],'>',$_[0]);
    }
    else {
        return expr_binary($_[0],'>',$_[1]);
    }
}

sub expr_gte {
    if ($_[2]) {
        return expr_binary($_[1],'>=',$_[0]);
    }
    else {
        return expr_binary($_[0],'>=',$_[1]);
    }
}

sub expr_plus {
    if ($_[2]) {
        return expr_binary($_[1],'+',$_[0]);
    }
    else {
        return expr_binary($_[0],'+',$_[1]);
    }
}

sub expr_minus {
    if ($_[2]) {
        return expr_binary($_[1],'-',$_[0]);
    }
    else {
        return expr_binary($_[0],'-',$_[1]);
    }
}

sub expr_multiply {
    if ($_[2]) {
        return expr_binary($_[1],'*',$_[0]);
    }
    else {
        return expr_binary($_[0],'*',$_[1]);
    }
}

sub expr_divide {
    if ($_[2]) {
        return expr_binary($_[1],'/',$_[0]);
    }
    else {
        return expr_binary($_[0],'/',$_[1]);
    }
}


sub like {
    return expr_binary($_[0],'LIKE',$_[1]);
}


sub expr_not {
    my $e1 = shift;
    my $expr = __PACKAGE__->new('NOT ('.$e1.')', $e1->bind_values);
    $expr->op('NOT');
    return $expr;
}


sub is_null {
    my $e = shift;
    my $expr = __PACKAGE__->new($e .' IS NULL', $e->bind_values);
    $expr->op('IS NULL');
    return $expr;
}


sub is_not_null {
    my $e = shift;
    my $expr = __PACKAGE__->new($e .' IS NOT NULL', $e->bind_values);
    $expr->op('IS NOT NULL');
    return $expr;
}


sub in {
    my $expr1 = shift;
    my @bind = $expr1->bind_values;
    my @exprs;

    foreach my $e (@_) {
        if (isa($e, __PACKAGE__)) {
            push(@exprs, $e);
            push(@bind, $e->bind_values);
        }
        elsif (ref($e) and ref($e) eq 'ARRAY') {
            push(@exprs, map {'?'} @$e);
            push(@bind, @$e);
        }
        else {
            push(@exprs, '?');
            push(@bind, $e);
        }
    }

    return __PACKAGE__->new($expr1 .' IN ('.join(', ',@exprs).')', @bind);
}


sub not_in {
    my $expr1 = shift;
    my @bind = $expr1->bind_values;
    my @exprs;

    foreach my $e (@_) {
        if (isa($e, __PACKAGE__)) {
            push(@exprs, $e);
            push(@bind, $e->bind_values);
        }
        elsif (ref($e) and ref($e) eq 'ARRAY') {
            push(@exprs, map {'?'} @$e);
            push(@bind, @$e);
        }
        else {
            push(@exprs, '?');
            push(@bind, $e);
        }
    }

    return __PACKAGE__->new($expr1 .' NOT IN ('.join(', ',@exprs).')', @bind);
}


sub between {
    my $expr1 = shift;
    my @bind = $expr1->bind_values;
    my @exprs;

    if (@_ != 2) {
        croak 'between($a,$b)';
    }

    foreach my $e (@_) {
        if (isa($e, __PACKAGE__)) {
            push(@exprs, $e);
            push(@bind, $e->bind_values);
        }
        else {
            push(@exprs, '?');
            push(@bind, $e);
        }
    }

    my $new =  __PACKAGE__->new($expr1 .' BETWEEN '.
                                 join(' AND ', @exprs), @bind);
    $new->multi(1);
    return $new;
}


sub not_between {
    my $expr1 = shift;
    my @bind = $expr1->bind_values;
    my @exprs;

    if (@_ != 2) {
        croak 'between($a,$b)';
    }

    foreach my $e (@_) {
        if (isa($e, __PACKAGE__)) {
            push(@exprs, $e);
            push(@bind, $e->bind_values);
        }
        else {
            push(@exprs, '?');
            push(@bind, $e);
        }
    }

    my $new =  __PACKAGE__->new($expr1 .' NOT BETWEEN '.
                                 join(' AND ', @exprs), @bind);
    $new->multi(1);
    return $new;
}


1;
__END__
# vim: set tabstop=4 expandtab:


=head1 NAME

SQL::DB::Schema::Expr - description

=head1 SYNOPSIS

  use SQL::DB::Schema::Expr;

=head1 DESCRIPTION

B<SQL::DB::Schema::Expr> is ...

=head1 METHODS

=head2 new



=head2 _clone



=head2 as



=head2 _as



=head2 val



=head2 set_val



=head2 reset_bind_values



=head2 push_bind_values



=head2 bind_values



=head2 multi



=head2 op



=head2 as_string



=head2 bind_values_sql



=head2 _as_string



=head2 expr_binary



=head2 expr_eq



=head2 expr_ne



=head2 expr_and

=head2 expr_or

=head2 and

=head2 or

=head2 and_not

=head2 or_not



=head2 expr_lt



=head2 expr_lte



=head2 expr_gt



=head2 expr_gte



=head2 expr_plus



=head2 expr_minus


=head2 expr_multiply


=head2 expr_divide


=head2 expr_not


=head2 is_null

=head2 is_not_null


=head2 like


=head2 in


=head2 not_in


=head2 between


=head2 not_between


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
