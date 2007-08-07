#!/usr/bin/perl

package RabakLib::ConfFile;

use warnings;
use strict;

use RabakLib::Conf;
use Data::Dumper;
use Storable qw(dclone);

=pod

=head1 NAME

RabakLib::ConfFile - Read Conf Files

=head1 SYNOPSIS

Format very similar to postfix config files:

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

# simple! use this:
# sub IDENT0 { "[a-z_][a-z_0-9]*" }
# sub IDENT { IDENT0 . '(\.' . IDENT0 . ')*' };


sub filename {
    my $self= shift;
    return $self->{FILE};
}

sub conf {
    my $self= shift;
    return $self->{CONF};
}

sub print_set_list {
    my $self= shift;

    print "Available backup sets in \"" . $self->filename() . "\":\n";
    my $bFound= 0;
    my $oConf= $self->{CONF};
    for my $sBakSet (sort keys %{ $oConf->{VALUES} }) {
        next unless ref $oConf->{VALUES}{$sBakSet}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{title}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{source}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{target};
        my $oSet= RabakLib::Set->new($oConf, $sBakSet, 1);
        my $oTarget= $oSet->get_targetPath(); 
        my @oSources= $oSet->get_sourcePaths();
        next unless $oTarget && scalar @oSources;

        my @aSources= ();
        for (@oSources) {
            push @aSources, $_->getFullPath();
        }
        my $sSources= join '", "', @aSources;
        print "  $sBakSet - " . $oConf->{VALUES}{$sBakSet}->get_value("title")
            . ", backs up \"" . $sSources
            . "\" to \"" . $oTarget->getFullPath() . "\"\n";
        $bFound= 1;
    }
    print "None.\n" unless $bFound;
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

    $self->{CONF}= RabakLib::Conf->new();
    $self->{ERROR}= undef;
    $self->_read_file($sFile);
}

sub _read_file {
    my $self= shift;
    my $sFile= shift;
    my $iIncludeLine= shift || 0;

    my $fin;

    my $sOpener= $self->{FILE};

    $self->{FILE}= $sFile;

    unless (open ($fin, $sFile)) {
        my $sMsg= "Can't open config file \"$sFile\"";
        $sMsg .= ", included in \"$sOpener\", line $iIncludeLine" if $sOpener;
        $self->_error($sMsg);
    }

    my $sName= '';
    my $iLine= 0;
    while (my $sLine= <$fin>) {
    $iLine++;
    next if $sLine =~ /^#/;

        my $bIndent= 0;
        if ($sLine =~ s/^(\s+)//) {
            $bIndent = 1 
        }
        else {
            $sName= '';
        }

    $sLine =~ s/\s+$//;
    next if $sLine eq '';

    last if $sLine =~ /^END\s*$/;

    if ($sLine =~ /^INCLUDE\s+(.+)/) {
        my $sInclude= $1;
        my $sInclude2= $sInclude;

        $sInclude2= "$1/$sInclude2" if !-f $sInclude2 && $sFile =~ /(.*)\/(.+?)$/;

        # TODO: $sInclude2= "/etc/rabak/$sInclude" if !-f $sInclude2;

            $self->_read_file($sInclude2, $iLine);
            $self->{FILE}= $sFile;
            next;
        }

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
        my $hConf= $self->{CONF};

        my $sErrKey= '';
        for (@aKeys) {
            $sErrKey .= ".$sKey";
            if (defined $hConf->{VALUES}{$sKey} && !ref $hConf->{VALUES}{$sKey}) {
                $self->_expand();
                if (!ref $hConf->{VALUES}{$sKey}) {
                    $self->_error("Variable \"" . substr($sErrKey, 1) . "\" is not a structure", $iLine, $sLine);
                }
            }
            $hConf->{VALUES}{$sKey}= RabakLib::Conf->new() unless $hConf->{VALUES}{$sKey};
            $hConf= $hConf->{VALUES}{$sKey};
            $sKey= $_;
        }

        $sErrKey .= ".$sKey";
        if (ref $hConf->{VALUES}{$sKey}) {
            $self->_error("Can't assign string, variable \"" . substr($sErrKey, 1) . "\" is a structure", $iLine, $sLine);
        }

        # In case of a multiline, we need a newline at the end of each line
        if ($bIndent) {
            $hConf->{VALUES}{$sKey}= '' unless defined $hConf->{VALUES}{$sKey};
            $hConf->{VALUES}{$sKey} .= "\n" if length($hConf->{VALUES}{$sKey}) && substr($hConf->{VALUES}{$sKey}, -1) ne "\n";
            $hConf->{VALUES}{$sKey} .= "$sValue\n";
        }
        else {
            $hConf->{VALUES}{$sKey}= $sValue;
        }

        # $hConf->{$sKey}= (defined $hConf->{$sKey} && $bIndent && $hConf->{$sKey} ne '') ? $hConf->{$sKey} . "\n$sValue" : $sValue;
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
    my $hConf= shift;
    my $sKey= shift;

    for (keys %{ $hConf->{VALUES} }) {
        if (ref($hConf->{VALUES}{$_})) {
            $self->__expand($hConf->{VALUES}{$_}, "$sKey.$_");
            next;
        }
        if ($hConf->{VALUES}{$_} =~ /^\$($sIdent)$/s) {
            my $hConf1= $self->_line_expand(substr("$sKey.$_", 1), $1, 1);
            if ($hConf1) {
                $hConf->{VALUES}{$_}= dclone($hConf1);
                next;
            }
        }
        $hConf->{VALUES}{$_} =~ s/(?<!\\)\$($sIdent)/$self->_line_expand(substr("$sKey.$_", 1), $1, 0)/ges;
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
    my $hConf= $self->{CONF};
    my $sErrKey= '';
    for (@aKeys) {
        $sErrKey .= ".$sKey";
        if (!ref $hConf->{VALUES}{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is not a structure"; 
            return $bWantStructure ? undef : '$'.$sName;
        }
        $hConf= $hConf->{VALUES}{$sKey};
        $sKey= $_;
    }
    $sErrKey .= ".$sKey";
    if ($bWantStructure) {
        return undef if !ref $hConf->{VALUES}{$sKey};
    }
    else {
        if (!defined $hConf->{VALUES}{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is not defined"; 
            return '$'.$sName;
        }
        if (ref $hConf->{VALUES}{$sKey}) {
            $self->{ERROR}= "Failed to expand \"$sName0\": \"\$" . substr($sErrKey, 1) . "\" is a structure"; 
            return '$'.$sName;
        }
    }
    if ('$'.$sName eq $hConf->{VALUES}{$sKey}) {
        $self->_error("Recursion occured while expanding \"$sName\"");
    }
    $self->{DID_EXPAND}= 1;
    return $hConf->{VALUES}{$sKey};
}

1;
