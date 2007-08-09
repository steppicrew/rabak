#!/usr/bin/perl

package RabakLib::Path::Source;

use warnings;
use strict;

use FindBin qw($Bin);

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub Factory {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $sPath= $oOrigConf->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        $oOrigConf->set_value("type", $1);
        $oOrigConf->set_value("path", $sPath);
        logger->warn("Specifying type in source path is deprecated. Please set type in Source Object!");
    }
    my $sType= $oOrigConf->get_value("type");
    unless (defined $sType) {
       $sType= "file" unless $sType;
       $oOrigConf->set_value("type", $sType);
    } 
    $sType= ucfirst $sType;

    my $new;
    eval {
        require "$Bin/RabakLib/SourceType/$sType.pm";
        my $sClass= "RabakLib::SourceType::$sType";
        $new= $sClass->cloneConf($oOrigConf);
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            logger->error("Backup type \"" . $sType . "\" is not defined: $@");
        }
        else {
            logger->error("An error occured: $@");
        }
        return undef;
    }

    return $new;
}

sub cloneConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::cloneConf($oOrigConf);

    $new->set_value("name", $new->{NAME}) unless $new->get_value("name");
    return $new;
}

sub show {
    my $self= shift;
    print "source name: " . $self->get_value("name") . "\n";
    print "source path: " . $self->getFullPath() . "\n";
}

sub getFullPath {
    my $self= shift;
    my $sFullPath= $self->SUPER::getFullPath();
    return "[" . $self->get_value("type") . "]:$sFullPath";
}

sub collect_bakdirs {
    my $self= shift;
    my $sSubSetBakDay= shift || 0;

    my $sBakSet= $self->get_value('name');
    my $sBakDir= $self->get_bakset_target();
    my @sBakDir= ();
    my $sSubSet= '';

    while (<$sBakDir/*>) {
        next unless /^$sBakDir\/(.*)/;
        my $sMonthDir= $1;

        next unless -d "$sBakDir/$sMonthDir" && $sMonthDir =~ /^(\d\d\d\d\-\d\d)\.($sBakSet)$/;

        while (<$sBakDir/$sMonthDir/*>) {
            next unless /^$sBakDir\/$sMonthDir\/(.*)/;
            my $sDayDir= $1;
            # print "$sDayDir??\n";
            next unless -d $_ && $sDayDir =~ /^(\d\d\d\d\-\d\d\-\d\d)([a-z])?\.($sBakSet)$/;
            if ($sSubSetBakDay eq $1) {
                die "Maximum of 27 backups reached!" if $2 && $2 eq 'z';
                if (!$2) {
                    $sSubSet= 'a' if $sSubSet eq '';
                }
                else {
                    $sSubSet= chr(ord($2)+1) if $sSubSet le $2;
                }
            }
            push @sBakDir, "$sBakDir/$sMonthDir/$sDayDir";
            # print "$sDayDir\n";
        }
    }

    @sBakDir= sort { $b cmp $a } @sBakDir;

    unshift @sBakDir, $sSubSet if $sSubSetBakDay;

    return @sBakDir;
    # return wantarray ? (\$sBakDir, $sSubSet) : \$sBakDir;
}

1;
