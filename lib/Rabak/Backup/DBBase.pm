#!/usr/bin/perl

package Rabak::Backup::DBBase;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(Rabak::Backup);

use Data::Dumper;
use Rabak::Log;

our %sPackers = (
    bzip2 => { cmd => "bzip2", ext => "bz2"},
    gzip  => { cmd => "gzip" , ext => "gz"},
);

sub new {
    my $class= shift;
    
    my $self= $class->SUPER::new(@_);

    my $sPacker= lc $self->_getSourceValue("packer");

    logger->warn("Unknown packer '$sPacker'. Valid Values are: '"
        . join("', '", keys %sPackers)
        . "'. Using default 'bzip2'") if $sPacker && !$sPackers{$sPacker};

    $sPacker= "bzip2" unless $sPacker && $sPackers{$sPacker};
    $self->{PACKER} = $sPackers{$sPacker};

    bless $self, $class;
}

sub DEFAULT_USER {
    die "This function has to be overloaded!"
}

# IMPORTANT: define all used properties here, order will be used for show
sub sourcePropertyNames {
    my $self= shift;
    return ($self->SUPER::sourcePropertyNames(@_), 'dbuser', 'dbpassword');
}

sub getShowCmd {
    die "This function has to be overloaded!"
}

sub getProbeCmd {
    die "This function has to be overloaded!"
}

sub getDumpCmd {
    die "This function has to be overloaded!"
}

# DETECTED UNUSED: getValidDb
sub getValidDb {
    die "This function has to be overloaded!"
}

sub getUser {
    my $self= shift;
    my $sUser= $self->_getSourceValue('dbuser', $self->DEFAULT_USER());
    # simple taint
    $sUser =~ s/[^a-z0-9_]//g;
    return $sUser;
}

sub getPasswd {
    my $self= shift;
    my $sPassword= $self->_getSourceValue('dbpassword');
    return $sPassword;
}

sub _buildDbCmd {
    my $self= shift;
    my @sCommand= @_;
    
    my $sPassword= $self->getPasswd;
    
    my $sCommand= Rabak::Conf->ShellQuote(@sCommand);
    $sCommand=~ s/\{\{PASSWORD\}\}/$sPassword/ if defined $sPassword;
    return $sCommand;
}

sub _dbCmd {
    my $self= shift;
    my @sCommand= @_;
    $self->_getSource()->runCmd($self->_buildDbCmd(@sCommand));
}

sub _logCmd {
    my $self= shift;
    my $sLogPretext= shift;
    my @sCommand= @_;
    
    logger->info($sLogPretext . ': ' . Rabak::Conf->ShellQuote(@sCommand));
}

# TODO
# plan: build a tunnel, fetch the db, delete old baks, release tunnel
# TODO: option dump_oids
# TODO: support large objects (pg_dump -Fc)
sub _backup {
    my $self= shift;
    my $hMetaInfo= shift;
    
    my $oSourcePeer= $self->_getSource();
    my $oTargetPeer= $self->_getTarget();

    my %sValidDb= ();
    my @sDb= ();
    my $bFoundOne= 0;

    my $i= 0;
    $self->_dbCmd($self->getShowCmd());
    if ($self->getLastExit) {
        logger->error("show databases command failed with: " . $oSourcePeer->getError);
        return 9;
    }
    %sValidDb= $self->parseValidDb($oSourcePeer->getLastOut);

    my $sSource= $oSourcePeer->getValue("path");

    if ($sSource eq '*') {
        @sDb= sort keys %sValidDb;
    }
    else {
        for (split(/\s*,\s*/, $sSource)) {
            unless (defined $sValidDb{$_}) {
                logger->warn("Unknown database: \"$_\"");
                next;
            }
            unshift @sDb, $_;
        }
    }

    my $sZipCmd= $self->{PACKER}{cmd};
    my $sZipExt= $self->{PACKER}{ext};

    foreach my $sDb (@sDb) {
        my $sDestFile= $hMetaInfo->{DATA_DIR} . "/$sDb.$sZipExt";
        my @sProbeCmd= $self->getProbeCmd($sDb);
        $self->_logCmd('Running probe', @sProbeCmd);

        unless ($self->_pretend()) {
            $self->_dbCmd(@sProbeCmd);
            if ($oSourcePeer->getLastExit()) {
                my $sError= $oSourcePeer->getLastError();
                chomp $sError;
                logger->error("Probe failed. Skipping \"$sDb\": $sError");
                next;
            }
        }

        my @sDumpCmd= $self->getDumpCmd($sDb);
        $self->_logCmd('Running dump', @sDumpCmd, '|', $sZipCmd);

        my $oDumpPeer= $oSourcePeer;
        my $sPipeCmd= "cat > '$sDestFile'";
        
        my $sDumpCmd= $self->_buildDbCmd(@sDumpCmd) . " | " . Rabak::Conf->ShellQuote($sZipCmd);

        if ($oTargetPeer->isRemote()) {
            # if target is remote, dump on source peer and write output remotely to target
            # TODO: check if target and source are the same users on the same host
            $sPipeCmd= $oTargetPeer->buildSshCmd($sPipeCmd);
        }
        elsif ($oSourcePeer->isRemote()) {
            # if target is local and soure is remote, dump over ssh and write directly to file
            $oDumpPeer= $oTargetPeer;
            $sDumpCmd= $self->buildSshCmd($sDumpCmd);
        }

        # now execute dump command on target
        unless ($self->_pretend()) {
            $oDumpPeer->_dbCmd("$sDumpCmd | $sPipeCmd");
            if ($oDumpPeer->getLastExit) {
                my $sError= $oDumpPeer->getLastError;
                chomp $sError;
                logger->error("Dump failed. Skipping dump of \"$sDb\": $sError");
                $hMetaInfo->{FAILED_FILE_CALLBACK}->("$sDestFile") if $hMetaInfo->{FAILED_FILE_CALLBACK};
                next;
            }
            $hMetaInfo->{FILE_CALLBACK}->($sDestFile) if $hMetaInfo->{FILE_CALLBACK};
        }

        $bFoundOne= 1;
    }

    return $bFoundOne ? 0 : 9;
}

1;