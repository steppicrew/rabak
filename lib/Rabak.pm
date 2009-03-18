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
    
    return ("result" => 42);
}

sub do_SetList {
}

sub API {
    my $cmd= shift;
    my %params= @_;
    
    my %result;
    eval {
        no strict "refs";

        $cmd= "do_$cmd";
        %result= &$cmd(@_);
    };
    return undef if $@;
    
    return \%result;
}

1;

__END__

