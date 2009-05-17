
package SSH;

use strict;
use warnings;

use IPC::Run qw(start pump finish);

sub new {
    my $class = shift;

    my $self = { RUNNING => 0, };

    bless $self, $class;

    $self->{HANDLE} = $self->__init();

    $self->__run();

    return $self;
}

sub DESTROY {
    my $self = shift;

    $self->{HANDLE}->finish();
}

sub __init {
    my $self = shift;

    my $fSerialize = sub {
        my $sData = shift;
        $sData =~ s/\x00/\x01\x00/g;
        return $sData;
    };

    my $_sRemain= "";
    my $fDeserialize = sub {
        $_sRemain.= shift;
        my ($sData, $sEscape);
        if ($_sRemain=~ s/^(.*?)\x00\x00$//s) {
            $sData= $1;
            if ($_sRemain=~ s/^(.+)\n//) {
                $sEscape= $1;
            }
            else {
                $_sRemain= "\0\0$_sRemain";
            }
        }
        else {
            $sData= $_sRemain;
            $_sRemain= $sData=~ s/\x00$// ? "\0" : "";
        }
        $sData =~ s/\x01\x00/\x00/g;
        return ( $sData, $sEscape );
    };

    my $fEscape = sub {
        my $sText = shift;
        return "\0\0$sText\n";
    };

    my $fDummyStdIn   = sub { "\0" };
    my $fCurrentStdIn = sub {
        print '
            use strict;
            use warnings;
      
            sub serialize {
                my $sData= shift;
                $sData=~  s/\x00/\x01\x00/g;
                return $sData;
            }
    
            my $_sRemain= "";
            sub deserialize {
                $_sRemain.= shift;
                my ($sData, $sEscape);
                if ($_sRemain=~ s/^(.*?)\x00\x00$//s) {
                    $sData= $1;
                    if ($_sRemain=~ s/^(.+)\n//) {
                        $sEscape= $1;
                    }
                    else {
                        $_sRemain= "\0\0$_sRemain";
                    }
                }
                else {
                    $sData= $_sRemain;
                    $_sRemain= $sData=~ s/\x00$// ? "\0" : "";
                }
                $sData =~ s/\x01\x00/\x00/g;
                return ( $sData, $sEscape );
            }
            
            sub escape {
                my $sText= shift;
                return "\0\0$sText\n";
            }
    
            print escape("RUNNING");
      
            my $sLine;
            while ($sLine= <>) {
                
                print serialize("running: $_");
                print escape("EXIT 0");
            }
            __END__' . "\n";
    };

    my $fDummyStdOut =
      sub { print "#### UNEXPECTED OUTPUT :'", join( "', '", @_ ), "'\n" };
    my $fCurrentStdOut;
    my $fCurrentStdErr;

    $self->{SET_STDIN}  = sub { $fCurrentStdIn  = shift || $fDummyStdIn };
    $self->{SET_STDOUT} = sub { $fCurrentStdOut = shift || $fDummyStdOut };
    $self->{SET_STDERR} = sub { $fCurrentStdErr = shift || $fDummyStdOut },;

    my $fStdIn = sub {
        my $sIn = $fCurrentStdIn->();
        return $sIn if defined $sIn;
        $fCurrentStdIn = $fDummyStdIn;
        return $fCurrentStdIn->();
    };
    my $fStdOut = sub {
        for my $sText (@_) {
            my $iExitCode = $2 if $sText =~ s/^(.*)\n\[(\d+)\]\n/$1/;
            $fCurrentStdOut->($sText);
            next unless defined $iExitCode;
            $self->{RUNNING} = 0;
            $self->{SET_STDIN}->();
            $self->{SET_STDOUT}->();
            $self->{SET_STDERR}->();
            $self->{EXIT_CODE} = $iExitCode;
        }
    };

    my $fStdErr = sub {
        $fCurrentStdErr->(@_);
    };

    return start( 'perl', $fStdIn, $fStdOut, $fStdErr );
}

sub __run {
    my $self = shift;

    $self->{RUNNING} = 1;
    my $h = $self->{HANDLE};

    while ( $self->{RUNNING} ) {
        last unless $h->pumpable();
        $h->pump();
    }
    return $self->{EXIT_CODE};
}

sub run {
    my $self = shift;

}

1;
