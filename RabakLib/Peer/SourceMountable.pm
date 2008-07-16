#!/usr/bin/perl

package RabakLib::Peer::SourceMountable;

use warnings;
use strict;
use vars qw(@ISA);

@ISA = qw(RabakLib::Peer::Source RabakLib::Peer::Mountable);

=head1 DESCRIPTION

SourceMountable.pm is an abstract class for mountable source objects.
It decises whose method has to be called.

=over 4

=cut

sub sort_show_key_order {
    my $self= shift;
    (
        # overwrite Source's SUPER class with Mountable
        $self->RabakLib::Peer::Source::sort_show_key_order(
            sub{
                $self->RabakLib::Peer::Mountable::sort_show_key_order(@_);
            }
        ),
    );
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    # overwrite Source's SUPER class with Mountable
    return $self->RabakLib::Peer::Source::show(
        $hConfShowCache,
        sub{
            $self->RabakLib::Peer::Mountable::show(@_)
        },
    );
    
}

sub getPath {
    my $self= shift;
    return $self->RabakLib::Peer::Mountable::getPath(@_);
}

=back

=cut

1;
