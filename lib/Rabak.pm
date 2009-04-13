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
    
    return { error => 500, error_text => 'Not implemented' };
}

sub do_get_baksets {
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
        error => 0,
        baksets => $aSets,
    };
}

sub do_get_bakset_status {
    my $param= shift;

    # $param->{bakset}..

    return { error => 500, error_text => 'Not implemented' };
}

# STUB!
sub do_get_backup_result {
    my $param= shift;

    # $param->{bakset}
    # $param->{from}
    # $param->{until}

    # gebaut mit 20090409000021
    my $VAR1 = {
                  'rabak' => './rabak backup test',
                  'bakset' => 'example',
                  'blaim' => 'steppi@hamail.de',
                  'time' => {
                              'start' => '20090409000001',
                              'end' => '20090409000810',
                            },
                  'version' => '1',
                  'conf' => '/home/raisin/.rabak/rabak.cf',

          'target' => {
                        'name' => 'blubtarget',
                        'title' => 'Platte unterm Tisch'
                      },
          'source__1' => {
                         'time' => {
                                     'start' => '20090409000211',
                                     'end' => '20090409000810',
                                   },
                         'stats' => '140MB copied',
                         'name' => 'source_pg',
                         'path' => 'psql://localhost/bctiny',
                         'result' => '1'
                       },
          'source__0' => {
                         'warnings' => '3',
                         'errors' => '0',
                         'time' => {
                                     'end' => '20090409000210',
                                     'start' => '20090409000001'
                                   },
                         'stats' => '123 files written',
                         'name' => 'source0',
                         'path' => 'file:///',
                         'result' => '0'
                       }
    };
    return { error => 0, result => $VAR1 };
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
    return { error => 500, error_text => "Command '$cmd' unknown" } if $@;
    
    return $result;
}

1;

__END__

