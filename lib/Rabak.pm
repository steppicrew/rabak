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
    
    my $aSets= [];
    for my $oSet (Rabak::Set->GetSets($oConf)) {
        my $oTarget= $oSet->get_targetPeer();
        my $hData= {
            'title' => $oSet->get_value('title'),
            'name' => $oSet->get_full_name(),
            'target' => $oTarget->get_full_name(),
        };
        my $aSources= [];
        for my $oSource ($oSet->get_sourcePeers()) {
            my $hSourceData= {
                'name' => $oSource->get_full_name(),
            };
            push @$aSources, $hSourceData;
        }
        $hData->{sources}= $aSources;
        push @$aSets, $hData;
    }
    
    return {
        result => 0,
        sets => $aSets,
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

