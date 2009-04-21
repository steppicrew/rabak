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

sub _getJobs {
    my $oConf= shift;
    my $sJob= shift;
    
    return () unless defined $sJob;
    
    my @aJobs= Rabak::Job->GetJobs($oConf);
    return @aJobs if $sJob eq '*';
    for my $oJob (@aJobs) {
        return ($oJob) if $oJob->getFullName eq $sJob;
    }
    return ();
}

sub _ApiGetJobs {
    my $param= shift; # UNUSED

    my ($oConf, $sConfFileName)= _getConf();
    
    my $hJobs= {};
    for my $oJob (Rabak::Job->GetJobs($oConf)) {
        my $oTarget= $oJob->getTargetPeer();
        my $hData= {
            'title' => $oJob->getValue('title'),
            'name' => $oJob->getFullName(),
            'target' => $oTarget->getFullName(),
        };
        my $hSources= {};
        for my $oSource ($oJob->getSourcePeers()) {
            my $hSourceData= {
                'name' => $oSource->getFullName(),
            };
            $hSources->{$oSource->getName()}= $hSourceData;
        }
        $hData->{sources}= $hSources;
        $hJobs->{$oJob->getFullName()}= $hData;
    }
    
    return {
        error => 0,
        conf => {
            file => $sConfFileName,
            title => 'Raisin\'s Config',
            jobs => $hJobs,
        }
    };
}

sub _ApiGetJobStatus {
    my $param= shift;

    # $param->{job}..

    return { error => 500, error_text => 'Not implemented' };
}

# valid parameters:
#   job: name of the job or empty or '*' for all
#   target_uuid: target's uuid or empty or '*' for all
sub _ApiGetSessions {
    my $param= shift;


    my ($oConf, $sConfFileName)= _getConf();
    my $sJob= $param->{job};
    my $sTargetUuid= $param->{target_uuid} || '*';
    
    my @aJobs= _getJobs($oConf, $sJob);
    return {
        error => 500,
        error_text => "Job '$sJob' does not exist.",
    } unless @aJobs;

    my $hJobs= {};
    my $sMetaDir= Rabak::Job->GetMetaBaseDir();
    my @sSessionFiles= glob "$sMetaDir/$sTargetUuid/session.*";
    for my $oJob (@aJobs) {
        my $oTargetPeer= $oJob->getTargetPeer();
        
        my $sJob= $oJob->getFullName();
        my $sqJob= quotemeta $sJob;

        my $hSessionData= {
            conf_file => $sConfFileName,
            job => $sJob,
            target => {
                name => $oTargetPeer->getFullName(),
                path => $oTargetPeer->getFullPath(),
            },
            sessions => {},
        };
        
        my $regJob= qr/\/session\.\d+\.\d+\.$sqJob$/;
        for my $sSessionFile (grep {/$regJob/} @sSessionFiles) {
            my $sSessionName= $sSessionFile;
            $sSessionName=~ s/.*\///;
            $hSessionData->{sessions}{$sSessionName}= _parseSessionFile($sSessionFile);
        }
        $hJobs->{$sJob}= $hSessionData
    }
# print Dumper($hSessionData);

    return {
        error => 0,
        conf => {
            file => $sConfFileName,
            title => 'Raisin\'s Config',
            jobs => $hJobs,
        }
    };
}

sub _parseSessionFile {
    my $sSessionFile= shift;
    
    my $hSession= Rabak::ConfFile->new($sSessionFile)->conf()->getValues();
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
    
    return $hSession;
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
