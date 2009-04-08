#!/usr/bin/perl

package Rabak;

use warnings;
use strict;

# no warnings 'redefine';

use Rabak::Log;
use Rabak::ConfFile;

# use Rabak::Peer::Source;
# use Rabak::Peer::Target;
# use Rabak::Version;

use Data::Dumper;
# use File::Spec ();
# use POSIX qw(strftime);

sub do_test {
    # print Dumper(@_);
    
    return { result => 500, error => 'Not implemented' };
}

sub do_setlist {
    my $oConfFile= Rabak::ConfFile->new();
    my $oConf= $oConfFile->conf();
    my @sSets= Rabak::Set->GetSets($oConf);
    
    return {
        result => 0,
        sets => [ map {
            my $oSet= $_;
            {
                'title' => $oSet->get_value('title'),
                'name' => $oSet->getName(),
            };
        } @sSets ],
    };
}

sub do_setstatus {
    my $param= shift;

    # $param->{set}..

    return { result => 500, error => 'Not implemented' };
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

