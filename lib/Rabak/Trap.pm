package Rabak::Trap;

# trap signals for cleaning up

use strict;
use warnings;

use Rabak::Log;

sub new {
    my $class= shift;
    my $fCallBack= shift;

    my $self= {
    	signals => {},
    	terminated => undef,
    };

    my $sigHandler= sub {
	    logger()->warn(
	    	"\n**** Caught interrupt. Finishing information store...",
	        "Press [Ctrl-C] again to cancel (may result in db information loss)."
	    );
	    $self->restore();
	    $self->{terminated}= 1;
	    $fCallBack->() if $fCallBack;
    };

    for my $sSig ("INT", "TERM", "QUIT", "KILL") {
        $self->{signals}{$sSig}= $SIG{$sSig};
        $SIG{$sSig}= $sigHandler;
    }

    bless $self, $class;
}

sub terminated {
	return shift->{terminated};
}

sub restore {
    my $self= shift;

    # restore signal handler
    for my $sSig (keys %{ $self->{signals} }) {
        $SIG{$sSig}= $self->{signals}{$sSig} || '';
        delete $self->{signals}{$sSig};
    }

	return $self->terminated();
}

sub DESTROY {

	# TODO: Warn if $self->{signals} is not empty instead of calling restore

	shift->restore();
}

1;
