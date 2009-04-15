#!/usr/bin/perl

package Rabak;

# PRE ALPHA CODE!

use warnings;
use strict;

use Rabak::Log;
use Rabak::ConfFile;

use Data::Dumper;

sub _apiTest {
    # print Dumper(@_);
    
    return { error => 500, error_text => 'Not implemented' };
}

sub _apiGetBaksets {
    my $param= shift; # UNUSED

    my $oConfFile= Rabak::ConfFile->new();
    my $oConf= $oConfFile->conf();
    
    my $aSets= [];
    for my $oSet (Rabak::Set->GetSets($oConf)) {
        my $oTarget= $oSet->getTargetPeer();
        my $hData= {
            'title' => $oSet->getValue('title'),
            'name' => $oSet->getFullName(),
            'target' => $oTarget->getFullName(),
        };
        my $aSources= [];
        for my $oSource ($oSet->getSourcePeers()) {
            my $hSourceData= {
                'name' => $oSource->getFullName(),
            };
            push @$aSources, $hSourceData;
        }
        $hData->{sources}= $aSources;
        push @$aSets, $hData;
    }
    
    return {
        error => 0,
        confs => {
            '/home/raisin/.rabak/rabak.cf' => {
                title => 'Test config',
                baksets => $aSets,
            }
        }
    };
}

sub _apiGetBaksetStatus {
    my $param= shift;

    # $param->{bakset}..

    return { error => 500, error_text => 'Not implemented' };
}

=pod

sub _apiGet {
}

=cut

# STUB!
sub _apiGetSessions {
    my $param= shift;

    # $param->{bakset}
    # $param->{from}
    # $param->{until}

    # gebaut mit 20090409000021
    my $example1 = {
            'cmdline' => './rabak backup example',
            'bakset' => 'example',
            'blaim' => 'steppi@hamail.de',
            # 'version' => '1',

            'target' => {
                'name' => 'blubtarget',
                'title' => 'Platte unterm Tisch'
            },

            'sources' => {
                'source0' => {
                    'path' => 'file:///',
                },
                'source_pg' => {
                    'path' => 'psql://localhost/bctiny',
                },
            },

            'sessions' => {
                '20090409000001:20090409000810' => {
                    'time' => {
                        'start' => '20090409000001',
                        'end' => '20090409000810',
                    },
                    'target' => {
                        'uuid' => 'BF733C62-29F7-11DE-A32E-A9BFECDD0C97',
                    },
                    'sources' => {
                        'source_pg' => {
                            'time' => {
                                'start' => '20090409000211',
                                'end' => '20090409000810',
                            },
                            'stats' => '140MB copied',
                            'result' => '1'
                        },
                        'source0' => {
                            'warnings' => '3',
                            'errors' => '0',
                            'time' => {
                                'end' => '20090409000210',
                                'start' => '20090409000001'
                            },
                            'stats' => '123 files written',
                            'result' => '0'
                        },
                    },
                }
            },
    };

    return {
        error => 0,
        'baksets' => {
            '/home/raisin/.rabak/rabak.cf' => {
                'example' => $example1,
            },
        }
    };
}

sub API {
    my $params= shift;
    
    my $cmd= $params->{cmd};
    my $result;
    eval {
        no strict "refs";

        my $do_cmd= "_api$cmd";
        $result= &$do_cmd($params);
    };
    return { error => 500, error_text => "Command '$cmd' unknown" } if $@;
    
    return $result;
}

1;

__END__
