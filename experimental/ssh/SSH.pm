


package SSH;

use strict;
use warnings;

use IPC::Run qw(start pump finish);

sub new {
  my $class= shift;
  
  my $self= {
    RUNNING => 0,
  };
  
  bless $self, $class;
  
  $self->{HANDLE}= $self->__init();
  
  $self->__run();

  return $self;
}

sub DESTROY {
  my $self= shift;
  
  $self->{HANDLE}->finish();
}

sub __init {
  my $self= shift;

  my $fDummyStdIn= sub {''};
  my $fCurrentStdIn= sub {
    print '
      use strict;
      use warnings;
      
      print "\n";
      
      while (<>) {
        chomp;
        print "running: $_":
        print "\n";
      }
      __END__' . "\n";
  };

  my $fDummyStdOut= sub { print "#### UNEXPECTED OUTPUT :'", join("', '", @_), "'\n" };
  my $fCurrentStdOut;
  my $fCurrentStdErr;

  $self->{SET_STDIN}=  sub { $fCurrentStdIn=  shift || $fDummyStdIn };
  $self->{SET_STDOUT}= sub { $fCurrentStdOut= shift || $fDummyStdOut };
  $self->{SET_STDERR}= sub { $fCurrentStdErr= shift || $fDummyStdOut },;

  my $fStdIn= sub {
    my $sIn= $fCurrentStdIn->();
    return $sIn if defined $sIn;
    $fCurrentStdIn= $fDummyStdIn;
    return $fCurrentStdIn->();
  };
  my $fStdOut= sub {
    for my $sText (@_) {
      my $iExitCode= $2 if $sText=~ s/^(.*)\n\[(\d+)\]\n/$1/;
      $fCurrentStdOut->($sText);
      next unless defined $iExitCode;
      $self->{RUNNING}= 0;
      $self->{SET_STDIN}->();
      $self->{SET_STDOUT}->();
      $self->{SET_STDERR}->();
      $self->{EXIT_CODE}= $iExitCode;
    }
  }
  my $fStdErr= sub {
    $fCurrentStdErr->(@_);
  }

  return start('perl', $fStdIn, $fStdOut, $fStdErr);
}

sub __run {
  my $self= shift;
  
  $self->{RUNNING}= 1;
  my $h= $self->{HANDLE};
  
  while ($self->{RUNNING}) {
    break unless $h->pumpable();
    $h->pump();
  }
  return $self->{EXIT_CODE};
}

sub run {
  my $self= shift;
  
  
}




1;