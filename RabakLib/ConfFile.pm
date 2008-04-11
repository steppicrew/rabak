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
=over

=cut

sub new {
    my $class= shift;
    # if multiple files are specified, the first existing is used
    my @sFiles= @_;
    my $self= {
        FILE => undef,
        SEARCHPATHS => [map {/(.*)\/[^\/]+$/ ? $1 : '.'} grep { defined } @sFiles],
        ERROR => undef,
        CONF => RabakLib::Conf->new('*'),
    };
    bless $self, $class;
    
    # find first existing file
    my $sFile= (grep {defined && -f} @sFiles)[0];

    if (!defined $sFile && scalar @sFiles) {
        print "Error: No configuration found in '",
            join("', '", grep(defined, @sFiles)),
            "'!\n";
        return $self;
    }

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

=item print_set_list

Prints a list of available backup sets.

=cut

sub print_set_list {
    my $self= shift;
    
    return unless defined $self->filename();

    print "Available backup sets in \"" . $self->filename() . "\":\n";
    my $bFound= 0;
    my $oConf= $self->{CONF};
    for my $sBakSet (sort keys %{ $oConf->{VALUES} }) {
        next unless ref $oConf->{VALUES}{$sBakSet}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{title}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{source}
            && defined $oConf->{VALUES}{$sBakSet}->{VALUES}{target};
        my $oSet= RabakLib::Set->CloneConf($oConf->{VALUES}{$sBakSet});
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

=item print_all

Prints the complete, parsed configuration.

=cut

sub print_all {
    my $self= shift;

    print "# These are the resulting values of \"" . $self->filename() . "\":\n";
    print "# (Btw, this output may be used as a valid configuration file.)\n";
    $self->{CONF}->show();
}

sub _error {
    my $self= shift;
    my ($sMsg, $sFile, $iLine, $sLine)= @_;

    my $sError= "file \"$sFile\"";
    $sError .= ", line $iLine" if $iLine;
    $sError .= ": $sMsg.";
    $sError .= " ($sLine)" if $sLine;
    print "$sError\n";
    exit 3;
}

sub read_file {
    my $self= shift;

    # use absolute paths only (needed for includes)
    my $sFile= Cwd::abs_path(shift);
    $self->{CONF}= RabakLib::Conf->new('*');
    # $self->{CONF}= RabakLib::Conf->new($sFile);
    $self->{ERROR}= undef;
    $self->{FILE}= $sFile;
    $self->_read_file($sFile);
}

sub _read_file {
    my $self= shift;
    my $sFile= shift;
    my $sOpener= shift;
    my $iIncludeLine= shift || 0;

    my $fin;

    unless (open ($fin, $sFile)) {
        my $sMsg= "Can't open config file \"$sFile\"";
        $sMsg .= ", included in \"$sOpener\", line $iIncludeLine" if $sOpener;
        $self->_error($sMsg, $sFile);
    }

    my $sName= '';
    my $iLine= 0;
    my $sPrefix= undef;
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
        
        $sPrefix= undef, next if $sLine =~ /^\[\s*\]$/;
        $sPrefix= $1, next if $sLine =~ /^\[\s*($sIdent)\s*\]$/;

        if ($sLine =~ /^INCLUDE\s+(.+)/) {
            my $sInclude= $1;

            unless ($sInclude =~ /^\//) {

                # include file is relative
                my @sIncDirs= ();

                # look in dir of current file
                push @sIncDirs, $1 if $sFile =~ /(.*)\/[^\/]+$/;

                # ... or in search paths
                push @sIncDirs, @{$self->{SEARCHPATHS}};

                # filter for existing files
                my @sIncFiles= grep {-f} map {"$_/$sInclude"} @sIncDirs;

                # take the first existing file (if any)
                $sInclude= $sIncFiles[0] if scalar @sIncFiles;
            }
            # try reading file or raise error
            $self->_read_file($sInclude, $sFile, $iLine);
            next;
        }

        my $sValue;
        if ($bIndent) {
            $self->_error("Unexpected value", $sFile, $iLine, $sLine) unless $sName;

            $sValue= $sLine;
        }
        else {
            $self->_error("Syntax error", $sFile, $iLine, $sLine) unless $sLine =~ /^($sIdent)\s*=\s*(.*?)$/i;

            $sName= lc $1;
            $sName= "$sPrefix.$sName" if defined $sPrefix;
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
                    $self->_error("Variable \"" . substr($sErrKey, 1) . "\" is not a structure", $sFile, $iLine, $sLine);
                }
            }
            $hConf->{VALUES}{$sKey}= RabakLib::Conf->new($sKey, $hConf) unless $hConf->{VALUES}{$sKey};
            $hConf= $hConf->{VALUES}{$sKey};
            $sKey= $_;
        }

        $sErrKey .= ".$sKey";
        if (ref $hConf->{VALUES}{$sKey}) {
            $self->_error("Can't assign string, variable \"" . substr($sErrKey, 1) . "\" is a structure", $sFile, $iLine, $sLine);
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
    $self->_error($self->{ERROR}, $sFile) if $self->{ERROR};

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
                # correct name and parent conf to new location in conf tree
                $hConf->{VALUES}{$_}{NAME}= $_;
                $hConf->{VALUES}{$_}{PARENT_CONF}= $hConf;
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
    my $bWantStructure= shift;

    if ($sName0 eq $sName) {
        $self->_error("Recursion occured while expanding \"$sName\"", "<Unknown>");
    }
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
        $self->_error("Recursion occured while expanding \"$sName\"", "<Unknown>");
    }
    $self->{DID_EXPAND}= 1;
    return $hConf->{VALUES}{$sKey};
}

1;
