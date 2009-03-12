#!/usr/bin/perl

package Rabak;

use warnings;
use strict;

# no warnings 'redefine';

use Rabak::Log;
# use Rabak::Peer::Source;
# use Rabak::Peer::Target;
# use Rabak::Version;

use Data::Dumper;
# use File::Spec ();
# use POSIX qw(strftime);

sub do_test {
    print Dumper(@_);
    
}

sub API {
    my $cmd= shift;
    my %params= @_;
    

    $cmd= "do_$cmd";

    my %result;
    eval {
        no strict refs;
        # %result= 
        &$cmd(@_);
    };
    print $@;

    return %result;
}

1;
