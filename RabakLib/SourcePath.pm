#!/usr/bin/perl

package RabakLib::SourcePath;

use warnings;
use strict;

use FindBin qw($Bin);

use vars qw(@ISA);

@ISA = qw(RabakLib::Path);

sub new {
    my $class = shift;
    my $oSet= shift;
    my $sConfName= shift || "source";
    
    my $self= $class->SUPER::new($oSet, $sConfName);

    my $sPath= $self->get_value("path");
    if ($sPath && $sPath=~ s/^(\w+)\://) {
        $self->set_value("type", $1);
        $self->set_value("path", $sPath);
        $self->log($self->warnMsg("Specifying type in source path is deprecated", "Please set type in Source Object!"));
    }
    my $sFilter= $self->get_value("filter");
    unless (defined $sFilter) {
       $sFilter= $self->get_set_value("filter");
       # TODO: check if filter is set in backset or globally
       # $self->log($self->warnMsg("Specifying filter in bakset is deprecated", "Please set filter in Source Object!")) if $sFilter;
       $self->set_value("filter", $sFilter);
    } 
    my $sType= $self->get_value("type");
    unless (defined $sType) {
       $sType= $self->get_set_value("type"); 
       $self->log($self->warnMsg("Specifying type in bakset is deprecated", "Please set type in Source Object!")) if $sType;
       $sType= "file" unless $sType;
       $self->set_value("type", $sType);
    } 
    $sType= ucfirst $sType;
    eval {
        require "$Bin/RabakLib/SourceType/$sType.pm";
        my $oClass= "RabakLib::SourceType::$sType";
        bless $self, $oClass;
        $self->_init;
        1;
    } or die "could not find type '$sType':" . @!;

    unless ($self->get_value("keep")) {
        my $iKeep= $self->get_set_value("keep");
        if (defined $iKeep) {
            $self->set_value("keep", $iKeep);
            $self->log($self->warnMsg("Specifying keep option in bakset is deprecated",
                "Please set 'keep' in Source Object!"));
        }
    }

    return $self;
}

# Stub for inheritance
sub _init {
}

# Stub for inheritance
sub _show {
}

sub get_targetPath {
    my $self= shift;
    return $self->{SET}->get_targetPath if $self->{SET};
    return undef;
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
