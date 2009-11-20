#!/usr/bin/perl

use MooseX::Declare;

class Db::Session {

    has 'session_id';
    has 'title' => ( is => "rw" );
}

package main;

my $meta = Db::Session->meta();

         for my $attribute ( $meta->get_all_attributes ) {
             print "ATTR:", $attribute->name(), "\n";

             if ( $attribute->has_type_constraint ) {
                 print "  type: ", $attribute->type_constraint->name, "\n";
             }
         }

         for my $method ( $meta->get_all_methods ) {
             print "METH:", $method->name, "\n";
         }

print "---\n";

my $s= new Db::Session();
$s->title("hu");
print $s->dump();
