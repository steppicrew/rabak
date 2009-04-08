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
    
    return { result => 500, error => 'Test not implemented' };
}

sub do_setlist {
    return {
        result => 0,
        sets => [
            { title => 'ho' },
            { title => 'ha' },
        ]
    };
}

sub API {
    my $params= shift;
    
    my $cmd= lc($params->{cmd});
    my $result;
    eval {
        no strict "refs";

        my $do_cmd= "do_$cmd";
        $result= &$do_cmd($params);
    };
    return { result => 500, error => "Command '$cmd' unknown" } if $@;
    
    return $result;
}

1;

__END__

