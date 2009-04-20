#!/usr/bin/perl

package Rabak;

# PRE ALPHA CODE!

use warnings;
use strict;

use Rabak::Log;
use Rabak::ConfFile;

use Data::Dumper;

sub _ApiTest {
    # print Dumper(@_);
    
    return { error => 500, error_text => 'Not implemented' };
}

sub _getConf {
    my $oConfFile= Rabak::ConfFile->new();
    return $oConfFile->conf(), $oConfFile->filename() if wantarray;
    return $oConfFile->conf();
}

sub _getBakset {
    my $oConf= shift;
    my $sBakset= shift;
    
    for my $oSet (Rabak::Set->GetSets($oConf)) {
        return $oSet if $oSet->getFullName eq $sBakset;
    }
    return undef
}

sub _ApiGetBaksets {
    my $param= shift; # UNUSED

    my ($oConf, $sConfFileName)= _getConf();
    
    my $hSets= {};
    for my $oSet (Rabak::Set->GetSets($oConf)) {
        my $oTarget= $oSet->getTargetPeer();
        my $hData= {
            'title' => $oSet->getValue('title'),
            'name' => $oSet->getFullName(),
            'target' => $oTarget->getFullName(),
        };
        my $hSources= {};
        for my $oSource ($oSet->getSourcePeers()) {
            my $hSourceData= {
                'name' => $oSource->getFullName(),
            };
            $hSources->{$oSource->getName()}= $hSourceData;
        }
        $hData->{sources}= $hSources;
        $hSets->{$oSet->getFullName()}= $hData;
    }
    
    return {
        error => 0,
        conf => {
            file => $sConfFileName,
            title => 'Raisin\'s Config',
            baksets => $hSets,
        }
    };
}

sub _ApiGetBaksetStatus {
    my $param= shift;

    # $param->{bakset}..

    return { error => 500, error_text => 'Not implemented' };
}

# STUB!
sub _apiGetSessions_______stub {
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
                12 => {
                    'time' => {
                        'start' => '20090409000001 GMT',
                        'end' => '20090409000810 GMT',
                    },
                    'target' => {
                        'uuid' => 'BF733C62-29F7-11DE-A32E-A9BFECDD0C97',
                    },
                    'sources' => {
                        'source_pg' => {
                            'time' => {
                                'start' => '20090409000210 GMT',
                                'end' => '20090409000810 GMT',
                            },
                            'stats' => '140MB copied',
                            'result' => '1'
                        },
                        'source0' => {
                            'warnings' => '3',
                            'errors' => '0',
                            'time' => {
                                'end' => '20090409000210 GMT',
                                'start' => '20090409000001 GMT'
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
        conf => {
            file => '/home/raisin/.rabak/rabak.cf',
            title => 'Raisin\'s Config',
            baksets => {
                'example' => $example1,
            },
        }
    };
}

sub _ApiGetSessions {
    my $param= shift;


    my ($oConf, $sConfFileName)= _getConf();
    my $sBakset= $param->{bakset};
    
    my $oSet= _getBakset($oConf, $sBakset);
    return {
        error => 500,
        error_text => "Bakset '$sBakset' does not exist.",
    } unless $oSet;

    my $oTargetPeer= $oSet->getTargetPeer();
    my $sMetaDir= $oTargetPeer->getPath($oTargetPeer->GetMetaDir());
    
    my $hSessionData= {
        conf_file => $sConfFileName,
        bakset => $sBakset,
        target => {
            name => $oTargetPeer->getFullName(),
            path => $oTargetPeer->getFullPath(),
        },
        sessions => {},
    };
    
    my @sSessionFiles= $oTargetPeer->glob("$sMetaDir/session.*.$sBakset");
    for my $sSessionFile (@sSessionFiles) {
        my $sLocalSessionFile= $oTargetPeer->getLocalFile($sSessionFile, SUFFIX => '.session');
        my $hSession= Rabak::ConfFile->new($sLocalSessionFile)->conf()->getValues();
        my $sSessionName= $sSessionFile;
        $sSessionName=~ s/.*\///;
        my $hSources= {};
        my $iTotalBytes= 0;
        for my $sSource (split(/[\s\,]+/, $hSession->{sources})) {
            $sSource=~ s/^\&//;
            $hSources->{$sSource}= $hSession->{$sSource};
            $iTotalBytes+= $hSources->{$sSource}{total_bytes} || 0;
            delete $hSession->{$sSource};
        }
        $hSession->{sources}= $hSources;
        $hSession->{saved}= $iTotalBytes || '(unknown)';
        $hSessionData->{sessions}{$sSessionName}= $hSession;
    }

#print Dumper($hSessionData);

    return {
        error => 0,
        conf => {
            file => '/home/raisin/.rabak/rabak.cf',
            title => 'Raisin\'s Config',
            baksets => {
                $sBakset => $hSessionData,
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

        my $do_cmd= "_Api$cmd";
        $result= &$do_cmd($params);
    };
    return { error => 500, error_text => "Command '$cmd' unknown" } if $@;
    
    return $result;
}

1;

__END__
