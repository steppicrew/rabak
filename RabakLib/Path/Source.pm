#!/usr/bin/perl

package RabakLib::Path::Source;

use warnings;
use strict;

use FindBin qw($Bin);

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub Factory {

    my $class = shift;
    my $oSet= shift;
    my $sConfName= shift;

    my $self= $class->SUPER::new($oSet, $sConfName);

    my $sPath= $self->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\:\/\///) {
        $self->set_value("type", $1);
        $self->set_value("path", $sPath);
        $self->log($self->warnMsg("Specifying type in source path is deprecated. Please set type in Source Object!"));
    }
    my $sType= $self->get_value("type");
    unless (defined $sType) {
       $sType= "file" unless $sType;
       $self->set_value("type", $sType);
    } 
    $sType= ucfirst $sType;
    my $oFactory= undef;
    eval {
        require "$Bin/RabakLib/SourceType/$sType.pm";
        my $oClass= "RabakLib::SourceType::$sType";
        $oFactory= $oClass->new(%{$self->{VALUES}});
        unless ($oFactory->get_value("name")) {
            my $sName= '';
            $sName= $sConfName if $sConfName ne $oFactory->get_value("path");
            $sName=~ s/^\&//;
            $oFactory->set_value("name", $sName);
        }
        1;
    };
    if ($@) {
        if ($@ =~ /^Can\'t locate/) {
            $self->log($self->errorMsg("Backup type \"" . $sType . "\" is not defined: $@"));
        }
        else {
            $self->log($self->errorMsg("An error occured: $@"));
        }
        return undef;
    }
    return $oFactory;
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
