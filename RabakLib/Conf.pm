#!/usr/bin/perl

package RabakLib::Conf;

use warnings;
use strict;

use Data::Dumper;
use Storable qw(dclone);
use RabakLib::Log;

our $iElemNo= 0;

sub new {
    my $class = shift;
    my $sName= shift || "*" . ($iElemNo++);
    my $oParentConf= shift;
    
    my $self= {
        VALUES=> {},
        PARENT_CONF=> $oParentConf,
        NAME=> $sName,
        ERRORCODE=> undef,
    };

    bless $self, $class;
}

sub CloneConf {
    my $class= shift;
    my $oOrigConf= shift;

    my $new= $class->new($oOrigConf->{NAME}, $oOrigConf->{PARENT_CONF});
    # replace reference to $oOrigConf with $new
    # TODO: is this safe???
    $oOrigConf->{PARENT_CONF}{VALUES}{$oOrigConf->{NAME}}= $new;
    $new->{VALUES}= $oOrigConf->{VALUES};
#    $new->{VALUES}= dclone($oOrigConf->{VALUES});
    for my $oValue (values %{$new->{VALUES}}) {
        $oValue->{PARENT_CONF}= $new if ref $oValue && $oValue->isa('RabakLib::Conf');
    }

    return $new;
}

# Stub to override. A RabakLib::Conf is always valid.
sub get_validation_message {
    return undef;
}

sub splitValue {
    my $self = shift;
    my $sValue= shift;
    
    return undef unless defined $sValue;
    
    my @Result = split /(?<!\\)\s+/, $sValue; # ?; # for correct syntax highlighting
    return \@Result;
}

# joins array of value parts with spaces
# returns undef if there were an object or array is empty
sub joinValue {
    my $self = shift;
    my $aValue= shift;
    
    return undef unless defined $aValue;
    
    my $bError;
    my @sValues = map {
        if (ref eq "ARRAY") {
            my $sJoined= $self->joinValue($_);
            $bError = 1 unless defined $sJoined;
            $sJoined;
        }
        elsif (ref) {
            $bError= 1;
        }
        else {
            $self->remove_backslashes_part2($_);
        }
    } @$aValue;
    return undef if $bError;
    return undef unless scalar @sValues;
    return join " ", @sValues;
}

# gets array ref of preparsed value, separated by whitespaces
sub get_prep_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    
    return $self->splitValue(
        $self->remove_backslashes_part1(
            $self->get_raw_value($sName, $sDefault)
        )
    );
}

# gets value as written in config
sub get_raw_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    
    my $sValue= $self->get_property($sName);
    
    unless (defined $sValue) {
        return $self->{NAME} if lc($sName) eq 'name';      
        return $sDefault;
    }
    return $sDefault if ref $sValue;
    return $sDefault if $sValue eq '*default*';
    return $sValue;
}

sub remove_backslashes_part1 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    if ($sValue =~ /\\$/) {
        logger->warn("Conf-File contains lines ending with backslashes!");
    }

    # make every "~" preceeded by "." (not space to keep word separators)
    $sValue =~ s/\~/\.\~/g;
    # replace every double backslash with "\~"
    $sValue =~ s/\\\\/\\\~/g;
    return $sValue;
}

sub undo_remove_backslashes_part1 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    $sValue =~ s/\\\~/\\\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
}

sub remove_backslashes_part2 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    # Insert support for tab etc.. here
    # $sValue =~ s/\\t/\t/g;

    # remove all backslashes not followed by "~"
    $sValue =~ s/\\(?!\~)//g;
    # undo changes made in part1
    return $self->undo_remove_backslashes_part1($sValue);
}

sub remove_backslashes {
    my $self= shift;
    my $sValue= shift;

    return $self->remove_backslashes_part2($self->remove_backslashes_part1($sValue));
}

# returns scalar value (references to other objects are already resolved, backslashes are cleaned)
sub get_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    my $hRefStack= shift;
    
    my @sValues= $self->resolveObjects($sName, $hRefStack);
    my $sValue= $self->joinValue(\@sValues);
    unless (defined $sValue) {
        return $self->{NAME} if lc($sName) eq 'name';      
        return $sDefault;
    }
    return $sDefault if ref $sValue;
    return $sDefault if $sValue eq '*default*';
    return $sValue;
}

# TODO: Which is correct: get_property? get_value? get_prep_value? $oCOnf->{VALUES}?
sub get_value_required_message {
    my $self= shift;
    my $sField= shift;

    return "Required value \"" . $self->{NAME} . ".$sField\" missing." unless defined $self->get_property($sField);
    return undef;
}

# command line switches are set in /switch
# if not it's a simple property value
sub get_switch {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    
    my $sSwitch= $self->get_value("/switch.$sName");
    return $sSwitch if defined $sSwitch;
    return $self->get_value($sName, $sDefault);
}

# find property and return it as it is (scalar, object etc.)
sub get_property {
    my $self= shift;
    my $sName= shift;
    
    return undef unless defined $sName;
    return undef if $sName eq '.';
    
    # leading slash means: search from root conf
    if ($sName=~ /^\//) {
        return $self->{PARENT_CONF}->get_property($sName) if $self->{PARENT_CONF};
        $sName=~ s/^[\/\.]+//;
    }
    
    # each leading dot means: going up one level in conf tree
    if ($sName=~ s/^\.//) {
        return $self->{PARENT_CONF}->get_property($sName) if $self->{PARENT_CONF};
        # if on top conf, get property here
        $sName=~ s/^\.*//;
    }
    
    $sName= lc $sName;

    my $oProp= $self;
    my $oParentProp= $self->{PARENT_CONF};
    my @sName= split(/\./, $sName);
    for (@sName) {
        unless (ref $oProp && defined $oProp->{VALUES}{$_}) {
            return $self->{PARENT_CONF}->get_property($sName) if $self->{PARENT_CONF}; 
            return undef;
        }
        $oParentProp= $oProp;
        $oProp= $oProp->{VALUES}{$_};
    }
    return ($oProp, $oParentProp) if wantarray;
    return $oProp;
}

sub get_node {
    my $self= shift;
    my $sName= shift;
    
    my $oConf= $self->get_property($sName);
    return $oConf if ref $oConf;
    return undef;
}

sub set_values {
    my $self= shift;
    my $hValues= shift;
    for my $sName (keys(%$hValues)) {
        $self->set_value($sName, $hValues->{$sName}) if defined $hValues->{$sName};
    }
}

sub set_value {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sValue= shift;

    # go up one level for each starting "." or go to top level for $sName starting with "/"
    $self= $self->{PARENT_CONF} while $self->{PARENT_CONF} && ($sName=~ s/^\.// || $sName=~ /^\//);
    $sName=~ s/^[\.\/]+//;

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for (@sName) {
        $self->{VALUES}{$_}= RabakLib::Conf->new($_, $self) unless ref $self->{VALUES}{$_};
        $self= $self->{VALUES}{$_};
    }
    
    # TODO: only allow assignment of undef to refs?
    $self->{VALUES}{$sName}= $sValue;
}

# expand macro given in $sMacroName
# returns hashref with expanded macro
# calls $fExpand->() for expanding macro's content
# calls $fPrePars-() for preparsing macros content
sub expandMacro {
    my $self= shift;
    my $sMacroName= shift;
    my $hMacroStack= shift || {};
    my $oScope= shift || $self;
    my $fExpand= shift || sub {$self->_resolveObjects(@_)}; # try to expand macro as deep as possible by default
    my $fPreParse= shift || sub {shift}; # no preparsing by default

    my %sResult= ();

# print "Scope: ", $oScope->get_full_name(), "\n";
# print "Expanding $sMacroName\n";

    $sMacroName=~ s/^\&//;
    my ($sMacro, $oMacroScope)= $oScope->get_property($sMacroName); 
    unless ($oMacroScope) {
        return {ERROR => "Unknown Macro '$sMacroName'"};
    }
    $sMacroName= $oMacroScope->get_full_name($sMacroName);

    if ($hMacroStack->{$sMacroName}) {
        $sResult{ERROR}= "Recursion detected ('$sMacroName').";
    }
    else {
        if (!defined $sMacro) {
            $sResult{ERROR}= "'$sMacroName' does not exist.";
        }
        else {
            $sResult{MACRO}= $sMacroName;
            if (ref $sMacro) {
                $sResult{DATA}= [$sMacro];
                $sResult{ERROR}= "'$sMacroName' is an object.";
            }
            else {
                my $aMacro= $self->splitValue(
                    $fPreParse->(
                        $self->remove_backslashes_part1($sMacro)
                    )
                );
                # build full macro name
                $hMacroStack->{$sMacroName}= 1;
# print "Macro: $sMacro\n";
                $sResult{DATA}= $fExpand->($aMacro, $hMacroStack, $oMacroScope);
                $hMacroStack->{$sMacroName} = 0;
            }
        }
    }
#    return $sResult{DATA};
# print "Done $sMacroName\n";
    return \%sResult;
}

sub resolveObjects {
    my $self= shift;
    my $sProperty= shift;
    my $hStack= shift || {};
    
    return map {$self->remove_backslashes_part2($_)} @{$self->_resolveObjects(["&$sProperty"], $hStack, $self)};
}

sub _resolveObjects {
    my $self= shift;
    my $aValue= shift;
    my $hStack= shift || {};
    my $oScope= shift || $self;

    my @oResult= ();
    
    for my $sValue (@$aValue) {
        # simple scalars are copied to @oResult
        unless ($sValue=~ s/^\&//) {
            push @oResult, $sValue;
            next;
        }
        # macros are expanded and result added to @oResult
# print "expanding macro: '$sValue'\n";
# print "scope: ", $self->get_full_name() , "\n";
        my $hResult = $self->expandMacro($sValue, $hStack, $oScope, sub{$self->_resolveObjects(@_)});
        unless (defined $hResult->{DATA}) {
            # logger->error($hResult->{ERROR}) if $hResult->{ERROR};
            next;
        }
# print "got ", Dumper($hResult->{DATA}), "\n";
        unless (ref $hResult->{DATA} eq "ARRAY") {
            logger->error("Internal error: expandMacro() should return an array reference! ($hResult->{DATA})");
            return [];
        }
        push @oResult, @{$hResult->{DATA}};
    }
    return \@oResult;
}

sub sort_show_key_order {
    return ();
}

sub sort_show_keys {
    my $self= shift;
    my @sKeys= @_;
    
    my @sSortOrder= $self->sort_show_key_order();
    my @sResult= ();
    for my $sSort (@sSortOrder) {
        for (my $i= 0; $i < scalar @sKeys; $i++) {
            my $sKey= $sKeys[$i];
            $sKey= $1 if $sKey=~ /\.([^\.]+)$/;
            if ($sKey eq $sSort) {
                push @sResult, splice(@sKeys, $i, 1);
                last;
            }
        }
    }
    push @sResult, sort(@sKeys);
    return @sResult;
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};

    my $sKey= $self->get_full_name();

    return if $sKey=~ /\*\d+$/; # don't show anonymous objects

    my $bKeyInvalid= 1;    

    $hConfShowCache->{"..references"}= {} unless $hConfShowCache->{"..references"};
    for ($self->sort_show_keys(keys %{ $self->{VALUES} })) {
        next if $_ =~ /^\./;
        if (ref($self->{VALUES}{$_})) {
            # print Dumper($self->{VALUES}{$_}); die;
            print "\n";
            $self->{VALUES}{$_}->show($hConfShowCache);
            $bKeyInvalid= 1;
            next;
        }
        # to get all references (objects will not change $hReferences and should be handled later)
        $self->get_value($_, undef, $hConfShowCache->{"..references"});
        # get the original config entry
        my $sValue= $self->get_raw_value($_) || '';
        $sValue =~ s/\n/\n\t/g;

        # $_= "$sKey.$_";
        # s/^\*.//;
        # print "$_ = $sValue\n";

        unless (defined $hConfShowCache->{"$sKey.$_"}) {
            print "[$sKey]\n" if $bKeyInvalid;
            $bKeyInvalid= 0;
            print "$_ = $sValue\n";
        }
        $hConfShowCache->{"$sKey.$_"}= 1;
    }
#    my @sReferences= grep {! defined $hConfShowCache->{$_}} keys %$hReferences;
#    print "# References: '&/", join("', '&/", @sReferences), "'\n" if @sReferences;
    print "[]\n" unless $bKeyInvalid;
}

sub get_full_name {
    my $self= shift;
    my $sName= shift || '';
    
    $sName=~ s/^.*\.//;
    while ($self->{PARENT_CONF}) {
        $sName= "$self->{NAME}.$sName";
        $self= $self->{PARENT_CONF};
    }
    $sName=~ s/\.$//;
    return $sName;
}

1;
