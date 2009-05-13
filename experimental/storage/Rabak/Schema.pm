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

1;
