
package SSH;

use strict;
use warnings;

use IPC::Run qw(start pump finish);
use SshStub;

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

    $self->{HANDLE}->finish() if $self->{HANDLE};
}

sub __init {
    my $self = shift;

    my $fSerialize = SshStub::Serialize();

    my $fDeserialize = SshStub::Deserialize();

    my $fEscape = SshStub::Escape();

    my $fDummyStdIn = sub { undef };
    my $fCurrentStdIn;

    my $fDummyStdOut = sub {
        print "#### UNEXPECTED OUTPUT: '", join( "', '", @_ ), "'\n";
    };
    my $fDummyStdErr = sub {
        print "#### UNEXPECTED ERROR: '", join( "', '", @_ ), "'\n";
    };
    my $fCurrentStdOut;
    my $fCurrentStdErr;

    $self->{SET_STDIN}  = sub { $fCurrentStdIn  = shift || $fDummyStdIn; };
    $self->{SET_STDOUT} = sub { $fCurrentStdOut = shift || $fDummyStdOut; };
    $self->{SET_STDERR} = sub { $fCurrentStdErr = shift || $fDummyStdErr; },;

    my $fStdIn = sub {
        my $sIn = $fCurrentStdIn->();
        return $fSerialize->($sIn) if defined $sIn;
        $fCurrentStdIn = $fDummyStdIn;
        return $fSerialize->($fCurrentStdIn->());
    };
    my $fStdOut = sub {
        for my $sText (@_) {
            my $sEscape;
            ($sText, $sEscape)= $fDeserialize->($sText);
print "[$sText]" if defined $sText;
print "[ESCAPE $sEscape]" if defined $sEscape;
print "\n";
            $fCurrentStdOut->($sText) if defined $sText;
            my $iExitCode = $1 if $sEscape && $sEscape =~ /^\[(\d+)\]$/;
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

    my $fh;
    open $fh, 'SshStub.pm' or die "Could not open file 'SshStub.pm'!";
    my @sScript = (<$fh>);
    push @sScript, "\nrun();\n__END__\n";
    $self->{SET_STDIN}->( sub { return shift @sScript; } );
    $self->{SET_STDOUT}->();
    $self->{SET_STDERR}->();
    
    return start( ['perl'], $fStdIn, $fStdOut, $fStdErr );
}

sub __run {
    my $self = shift;

    $self->{RUNNING} = 1;
    my $h = $self->{HANDLE};

    while ( $self->{RUNNING} ) {
#print "*\n";
        last unless $h->pumpable();
#print "**\n";
        $h->pump();
#print "***\n";
    }
    return $self->{EXIT_CODE};
}

sub run {
    my $self  = shift;
    my @sText = (shift);
    $self->{SET_STDIN}->( sub  { shift @sText } );
    $self->{SET_STDOUT}->( sub { print join('-', @_); } );
    $self->{SET_STDERR}->( sub { print "ERROR: ", join('-', @_); } );
    print "Result: ", $self->__run(), "\n";
}

1;
