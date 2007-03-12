#!/usr/bin/perl

package RabakLib::ConfFile;

use warnings;
use strict;

use RabakLib::Conf;
use Data::Dumper;
use Storable qw(dclone);

=pod

=head1 NAME

RabakCf - Read Conf Files

=head1 SYNOPSYS

Format very similar to postfix config files:2

    key1 = value1
    key2 = multi
        lined           # indent the following lines
    key3.prop1 = $key1  # -> key3.prop1 = value1
    key3.prop2 = $key1
        $key2           # -> key3.prop2 = value1 \n multi \n lined
    key4.prop3= $key3   # -> key4.prop3.prop1 = value1
                        #    key4.prop3.prop2 = value1 \n multi \n lined
=cut

sub new {
    my $class= shift;
    my $sFile= shift;
    my $self= {
        FILE => undef,
        CONF => undef,
        ERROR => undef,
    };
    bless $self, $class;
    $self->read_file($sFile) if $sFile;
    return $self;
}

# TODO: In a perfect world, these would be constants:

our $sIdent0= "[a-z_][a-z_0-9]*";
our $sIdent= "$sIdent0(\\.$sIdent0)*";

sub filename {
    my $self= shift;
    return $self->{FILE};
}

sub conf {
    my $self= shift;
    return $self->{CONF};
}

sub _error {
    my $self= shift;
    my ($sMsg, $iLine, $sLine)= @_;

    my $sError= "file \"" . $self->{FILE} . "\"";
    $sError .= ", line $iLine" if $iLine;
    $sError .= ": $sMsg.";
    $sError .= " ($sLine)" if $sLine;
    print "$sError\n";
    exit 3;
}

sub read_file {
    my $self= shift;
    my $sFile= shift;

    my $fin;

    $self->{FILE}= $sFile;
    $self->{CONF}= RabakLib::Conf->new();
    $self->{ERROR}= undef;

    open $fin, $sFile or $self->_error("Can't open config file \"$sFile\"");
    my $sName= '';
    my $iLine= 0;
    while (my $sLine= <$fin>) {
	$iLine++;
	next if $sLine =~ /^#/;

	$sLine =~ s/^(\s+)//;
	my $bIndent= 1 if $1;
	$sName= '' unless $bIndent;
	$sLine =~ s/\s+$//;
	next if $sLine eq '';


        last if $sLine eq 'END';


        my $sValue;
	if ($bIndent) {
            $self->_error("Unexpected value", $iLine, $sLine) unless $sName;
            $sValue= $sLine;
	}
	else {
            $self->_error("Syntax error", $iLine, $sLine) unless $sLine =~ /^($sIdent)\s*=\s*(.*?)$/i;

	    $sName= $1;
	    $sValue= $3;
	}

        my @aKeys= split(/\./, $sName);
        my $sKey= shift @aKeys;
        my $xr= $self->{CONF};

        my $sErrKey= '';
        for (@aKeys) {
            $sErrKey .= ".$sKey";
            if (defined $xr->{$sKey} && !ref $xr->{$sKey}) {
                $self->_expand();
                if (!ref $xr->{$sKey}) {
                    $self->_error("Variable \"" . substr($sErrKey, 1) . "\" is not a structure", $iLine, $sLine);
                }
            }
            $xr->{$sKey}= RabakLib::Conf->new() unless $xr->{$sKey};
            $xr= $xr->{$sKey};
            $sKey= $_;
        }

        $sErrKey .= ".$sKey";
        if (ref $xr->{$sKey}) {
            $self->_error("Can't assign string, variable \"" . substr($sErrKey, 1) . "\" is a structure", $iLine, $sLine);
        }

        # In case of a multiline, we need a newline at the end of each line
        if ($bIndent) {
            $xr->{$sKey}= '' unless defined $xr->{$sKey};
            $xr->{$sKey} .= "\n" if length($xr->{$sKey}) && substr($xr->{$sKey}, -1) ne "\n";
            $xr->{$sKey} .= "$sValue\n";
        }
        else {
            $xr->{$sKey}= $sValue;
        }

	# $xr->{$sKey}= (defined $xr->{$sKey} && $bIndent && $xr->{$sKey} ne '') ? $xr->{$sKey} . "\n$sValue" : $sValue;
    }

    $self->_expand();
    $self->_error($self->{ERROR}) if $self->{ERROR};

    return $self->{CONF};
}

sub _expand {
    my $self= shift;

    $self->{DID_EXPAND}= 1;
    while ($self->{DID_EXPAND}) {
        $self->{DID_EXPAND}= 0;
        $self->{ERROR}= '';                     # TODO: Ok to do this here?
        $self->__expand($self->{CONF}, '');
    }
}

sub __expand {
    my $self= shift;
    my $xr= shift;
    my $sKey= shift;

    for (keys %{ $xr }) {
        if (ref($xr->{$_})) {
            $self->__expand($xr->{$_}, "$sKey.$_");
            next;
        }
        if ($xr->{$_} =~ /^\$($sIdent)$/s) {
            my $xr1= $self->_line_expand(substr("$sKey.$_", 1), $1, 1);
            if ($xr1) {
                $xr->{$_}= dclone($xr1);
                next;
            }
        }
        $xr->{$_} =~ s/\$($sIdent)/$self->_line_expand(substr("$sKey.$_", 1), $1, 0)/ges;
    }
}

sub _line_expand {
    my $self= shift;
    my $sName0= shift;
    my $sName= shift;

    if ($sName0 eq $sName) {
        $self->_error("Recursion occured while expanding \"$sName\"");
    }
    my $bWantStructure= shift;
    my @aKeys= split(/\./, $sName);
    my $sKey= shift @aKeys;
    my $xr= $self->{CONF};
    my $sErrKey= '';
    for (@aKeys) {
        $sErrKey .= ".$sKey";
        if (!ref $xr->{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is not a structure"; 
            return $bWantStructure ? undef : '$'.$sName;
        }
        $xr= $xr->{$sKey};
        $sKey= $_;
    }
    $sErrKey .= ".$sKey";
    if ($bWantStructure) {
        return undef if !ref $xr->{$sKey};
    }
    else {
        if (!defined $xr->{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is not defined"; 
            return '$'.$sName;
        }
        if (ref $xr->{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is a structure"; 
            return '$'.$sName;
        }
    }
    if ('$'.$sName eq $xr->{$sKey}) {
        $self->_error("Recursion occured while expanding \"$sName\"");
    }
    $self->{DID_EXPAND}= 1;
    return $xr->{$sKey};
}

1;
