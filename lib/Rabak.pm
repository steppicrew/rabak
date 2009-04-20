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

sub _getBaksets {
    my $oConf= shift;
    my $sBakset= shift;
    
    return () unless defined $sBakset;
    
    my @aSets= ();
    for my $oSet (Rabak::Set->GetSets($oConf)) {
        push @aSets, $oSet if $oSet->getFullName eq $sBakset || $sBakset eq '*';
    }
    return @aSets;
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

sub _ApiGetSessions {
    my $param= shift;


    my ($oConf, $sConfFileName)= _getConf();
    my $sBakset= $param->{bakset};
    
    my @aSets= _getBaksets($oConf, $sBakset);
    return {
        error => 500,
        error_text => "Bakset '$sBakset' does not exist.",
    } unless @aSets;

    my $hBaksets= {};
    for my $oSet (@aSets) {
        my $sMetaDir= $oSet->GetMetaBaseDir();
        my $oTargetPeer= $oSet->getTargetPeer();
        
        my $sBakset= $oSet->getFullName();

        my $hSessionData= {
            conf_file => $sConfFileName,
            bakset => $sBakset,
            target => {
                name => $oTargetPeer->getFullName(),
                path => $oTargetPeer->getFullPath(),
            },
            sessions => {},
        };
        
        my @sSessionFiles= glob "$sMetaDir/*/session.*.$sBakset";
        for my $sSessionFile (@sSessionFiles) {
            my $hSession= Rabak::ConfFile->new($sSessionFile)->conf()->getValues();
            my $sSessionName= $sSessionFile;
            $sSessionName=~ s/.*\///;
            my $hSources= {};
            my $iTotalBytes= 0;
            my $iTransferredBytes= 0;
            my $iTotalFiles= 0;
            my $iTransferredFiles= 0;
            my $iFailedFiles= 0;
            for my $sSource (split(/[\s\,]+/, $hSession->{sources})) {
                $sSource=~ s/^\&//;
                $hSources->{$sSource}= $hSession->{$sSource};
                $iTotalBytes+= $hSources->{$sSource}{stats}{total_bytes} || 0;
                $iTransferredBytes+= $hSources->{$sSource}{stats}{transferred_bytes} || 0;
                $iTotalFiles+= $hSources->{$sSource}{stats}{total_files} || 0;
                $iTransferredFiles+= $hSources->{$sSource}{stats}{transferred_files} || 0;
                $iFailedFiles+= $hSources->{$sSource}{stats}{failed_files} || 0;
                delete $hSession->{$sSource};
            }
            $hSession->{sources}= $hSources;
            $hSession->{total_files}= $iTotalFiles || -1;
            $hSession->{transferred_files}= $iTransferredFiles || -1;
            $hSession->{failed_files}= $iFailedFiles || -1;
            $hSessionData->{sessions}{$sSessionName}= $hSession;
        }
        $hBaksets->{$sBakset}= $hSessionData
    }
# print Dumper($hSessionData);

    return {
        error => 0,
        conf => {
            file => '/home/raisin/.rabak/rabak.cf',
            title => 'Raisin\'s Config',
            baksets => $hBaksets,
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
    return { error => 500, error_text => "Command '$cmd' unknown\n$@" } if $@;
    
    return $result;
}

1;

__END__
