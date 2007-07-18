#!/usr/bin/perl

package RabakLib::Path;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use Data::Dumper;
use File::Spec ();
use File::Temp ();

use vars qw(@ISA);

@ISA = qw(RabakLib::PathBase);

sub new {
    my $class= shift;
    my $self= $class->SUPER::new(@_);
    bless $self, $class;
}

sub getFullPath {
    my $self= shift;
    # TODO: find a better way to get full path
    my $sPath= $self->get_value("path") ? $self->getPath(shift) : $self->get_value("db");

    if ($self->remote) {
        $sPath = $self->get_value("host") . "\:$sPath";
        $sPath = $self->get_value("user") . "\@$sPath" if $self->get_value("user");
    }
    return $sPath;
}

sub getPath {
    my $self= shift;
    my $sPath= shift || '.';

    return $sPath unless $self->get_value("path");

    $self->_set_value("path", $self->abs_path($self->get_value("path"))) unless File::Spec->file_name_is_absolute($self->get_value("path"));

    $sPath= File::Spec->canonpath($sPath); # simplify path
    $sPath= File::Spec->rel2abs($sPath, $self->get_value("path")) unless File::Spec->file_name_is_absolute($sPath);
    return $sPath;
}

1;
