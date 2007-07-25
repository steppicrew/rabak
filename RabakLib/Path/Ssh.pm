#!/usr/bin/perl

package RabakLib::Path::Ssh;

# wrapper class for ssh command

use warnings;
use strict;

use Data::Dumper;
use File::Temp ();
use vars qw(@ISA);

@ISA = qw(RabakLib::PathBase);

sub new {
    my $class= shift;
    my $self= $class->SUPER::new(@_);

    $self->{DEBUG}= 0;

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    bless $self, $class;
}

sub _ssh {
    die "Internal error: Ssh objects must not call sub _ssh()";
}
sub remote {
    # ssh is never remote
    return 0;
}

sub build_ssh_cmd {
    my $self= shift;
    my $sCmd= shift;

    die "Ssh.pm: No command specified!" unless defined $sCmd;
    die "Ssh.pm: No host specified!" unless defined $self->get_value("host");

    my @sSshCmd= ('ssh');

    push @sSshCmd, '-p', $self->get_value("port") if $self->get_value("port");
    if ($self->get_value("protocol")) {
        push @sSshCmd, '-1' if $self->get_value("protocol") eq "1";
        push @sSshCmd, '-2' if $self->get_value("protocol") eq "2";
    }
    if ($self->get_value("identity_files")) {
        push @sSshCmd, '-i', $_ for (split(/\s+/, $self->get_value("identity_files")));
    }
#    push @sSshCmd, '-vvv' if $self->{DEBUG};

    my $sHost= $self->get_value("user");
    $sHost=~ s/(?<=.)$/\@/;
    $sHost.= $self->get_value("host");
    push @sSshCmd, $sHost;
    push @sSshCmd, $sCmd;
    s/\'/\'\\\'\'/g for (@sSshCmd);
    return "'" . join("' '", @sSshCmd) . "'";
}

sub cmd {
    my $self= shift;
    my $sCmd= shift;
    my $sStdIn= shift;
    my $bPiped= shift || 0;

    my $sRunCmd= '';

    if (defined $sStdIn) {
        my $fh;
        if ($self->{STDIN}) {
            open $fh, ">$self->{STDIN}" or die "could not open file '$self->{STDIN}' for STDIN";
        }
        else {
            ($fh, $self->{STDIN}) = $self->local_tempfile;
        }
        print $fh $sStdIn if defined $sStdIn;
        close $fh;
        $sRunCmd.= "cat '$self->{STDIN}' | ";
    }

    $sRunCmd.= $self->build_ssh_cmd($sCmd);
    print "SSH: stdin [$sStdIn]\n######################\n" if $self->{DEBUG} && defined $sStdIn;
    print "SSH: running [$sRunCmd]\n" if $self->{DEBUG};
    return $self->_run_local_cmd($sRunCmd, $bPiped);
}

1;