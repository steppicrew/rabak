#!/usr/bin/perl

package RabakLib::Conf;

use warnings;
use strict;
no warnings 'redefine';

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

# define some regexp
our $sregIdent0= "[a-z_][a-z_0-9]*";
our $sregIdent= "$sregIdent0(\\.$sregIdent0)*";
our $sregIdentDef= "(\\*\\.)?$sregIdent";
our $sregIdentRef= "\\/?\\.*$sregIdent";

# ...and make them public
sub REGIDENT0   { $sregIdent0 }
sub REGIDENT    { $sregIdent };
sub REGIDENTDEF { $sregIdentDef };
sub REGIDENTREF { $sregIdentRef };

# clone
sub newFromConf {
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
    
    return [""] if $sValue eq "";
    my @Result = split /(?<!\\)[\s\,]+/, $sValue; # ?; # for correct syntax highlighting
    return \@Result;
}

# joins array of value parts with spaces
# returns undef if there was an object or array is empty
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
            # remove_backslashes_part2 should already have been called
#            $self->remove_backslashes_part2($_);
            $_;
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
    
    my $sValue= $self->find_property($sName);
    
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

    return $sValue unless defined $sValue;
    return $sValue if ref $sValue;

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

    return $sValue unless defined $sValue;
    return $sValue if ref $sValue;

    $sValue =~ s/\\\~/\\\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
}

sub remove_backslashes_part2 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless defined $sValue;
    return $sValue if ref $sValue;

    # Insert support for tab etc.. here
    # $sValue =~ s/\\t/\t/g;

    # remove all backslashes not followed by "~"
    $sValue =~ s/\\(?!\~)//g;

    # undo changes made in part1
    $sValue =~ s/\\\~/\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
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
    my $aRefStack= shift;
    
    my @sValues= $self->resolveObjects($sName, $aRefStack);
    my $sValue= $self->joinValue(\@sValues);
    unless (defined $sValue) {
        return $self->{NAME} if lc($sName) eq 'name';      
        return $sDefault;
    }
    return $sDefault if ref $sValue;
    return $sDefault if $sValue eq '*default*';
    return $sValue;
}

# TODO: Which is correct: find_property? get_value? get_prep_value? $oCOnf->{VALUES}?
sub get_value_required_message {
    my $self= shift;
    my $sField= shift;

    return "Required value \"" . $self->{NAME} . ".$sField\" missing." unless defined $self->find_property($sField);
    return undef;
}

# command line switches are set in /*.switch
# if not it's a simple property value
sub get_switch {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    my $aRefStack= shift;
    
    my $sResult= $self->get_value("/*.switch.$sName", undef, $aRefStack);
    return $sResult if defined $sResult;
    return $self->get_value("switch.$sName", $sDefault, $aRefStack);
}

# find property and return it as it is (scalar, object etc.)
sub find_property {
    my $self= shift;
    my $sName= shift;
 
    return undef unless defined $sName;

    # first look in '*'-scope
    unless ($sName =~ /\*/) {
        my $sStarName= $sName;
        $sStarName=~ s/^[\.\/]*//;

        # search for existing values in '/*'-scope ('*.zuppi' overwrites '*.zappi.zuppi')
        my $oRootScope= $self->find_scope("/*.$sStarName");
        my @sStarName= split(/\./, $sStarName);
        $sStarName= '';
        while (my $sSubKey= pop @sStarName) {
            $sStarName= ".$sSubKey$sStarName";
            my ($oValue, $oScope, $sKey)= $oRootScope->get_property("*$sStarName");
            if (defined $oValue) {
                return ($oValue, $oScope, $sKey) if wantarray;
                return $oValue;
            }
        }
    }

##     return $self->_find_property($sName);   
## }
##    
## # find property and return it as it is (scalar, object etc.)
## sub _find_property {
##     my $self= shift;
##     my $sName= shift;
    
    return undef unless defined $sName;
    return undef if $sName eq '.' || $sName eq '';
    
    my $oScope= $self->find_scope($sName);
    $sName=~ s/^\/?\.*//;
    
    $sName= lc $sName;

    while (defined $oScope) {
        my ($oProp, $oParentConf, $sKey)= $oScope->get_property($sName);
        if (defined $oProp) {
            return ($oProp, $oParentConf, $sKey) if wantarray;
            return $oProp;
        }
        $oScope= $oScope->{PARENT_CONF};
    }
    return undef;
}

# finds proper scope
sub find_scope {
    my $self= shift;
    my $sName= shift;
    
    return undef unless defined $sName;
    return undef if $sName eq '.' || $sName eq '';
    
    # leading slash means: search from root conf
    if ($sName=~ /^\//) {
        $self= $self->{PARENT_CONF} while $self->{PARENT_CONF};
        return $self;
    }
    
    # each leading dot means: going up one level in conf tree
    $self= $self->{PARENT_CONF} while $sName=~ s/^\.// && $self->{PARENT_CONF};
    return $self;
}

# finds given property, does not look in other scopes
# returns property, best fitting scope and remaining key
sub get_property {
    my $self= shift;
    my $sName= lc shift;

    return undef unless defined $sName;
    return undef if $sName eq '.' || $sName eq '';
    
    my $oScope= $self;
    my @sName= split(/\./, $sName);

    # get last key
    my $sPropKey= pop @sName;
    while (my $sKey= shift @sName) {
        unless (ref $oScope->{VALUES}{$sKey}) {

            # the join builds a key relative from last scope
            return (undef, $oScope, join('.', $sKey, @sName, $sPropKey)) if wantarray;
            return undef;
        }
        $oScope= $oScope->{VALUES}{$sKey};
    }
    return ($oScope->{VALUES}{$sPropKey}, $oScope, $sPropKey) if wantarray;
    return $oScope->{VALUES}{$sPropKey};
    
}

# deletes given property
sub remove_property {
    my $self= shift;
    my $sName= shift;
    
    my (undef, $oScope, $sKey)= $self->get_property($sName);
    delete $oScope->{VALUES}{$sKey} if defined $oScope && exists $oScope->{VALUES}{$sKey};
}

sub get_node {
    my $self= shift;
    my $sName= shift;
    
    my $oConf= $self->find_property($sName);
    return $oConf if ref $oConf;
    return undef;
}

sub preset_values {
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
        $self->{VALUES}{$_}= RabakLib::Conf->new($_, $self) unless exists $self->{VALUES}{$_};
        unless (ref $self->{VALUES}{$_}) {
            logger->error("'" . $self->get_full_name() . ".$_' is not an object!");
            exit 3;
        }
        
        $self= $self->{VALUES}{$_};
    }
    
    # TODO: only allow assignment of undef to refs?
    $self->{VALUES}{$sName}= $sValue;
}

# expand macro given in $sMacroName
# returns hashref with expanded macro
# calls $fExpand->() for expanding macro's content
# calls $fPrePars->() for preparsing macros content
sub expandMacro {
    my $self= shift;
    my $sMacroName= shift;
    my $oScope= shift || $self;
    my $aMacroStack= shift || [];
    my $fExpand= shift || sub { $self->_resolveObjects(@_) }; # try to expand macro as deep as possible by default
    my $fPreParse= shift || sub { shift }; # no preparsing by default

    my %sResult= ();

# print "Scope: ", $oScope->get_full_name(), "\n";
# print "Expanding $sMacroName\n";

    $sMacroName=~ s/^\&//;
    my ($sMacro, $oMacroScope)= $oScope->find_property($sMacroName); 
    unless ($oMacroScope) {
        return { ERROR => "Unknown Macro '$sMacroName'" };
    }
    # build full macro name
    $sMacroName= $oMacroScope->get_full_name($sMacroName);

    $aMacroStack->[0] = "[]" unless scalar @$aMacroStack;
    my $sMacroPath= $aMacroStack->[0];
    my $sqMacroName= quotemeta "[$sMacroName]";

    return { ERROR => "Recursion detected ('$sMacroName')." } if $sMacroPath=~ /$sqMacroName/;
    return { ERROR => "'$sMacroName' does not exist." } unless defined $sMacro;
    $sResult{MACRO}= $sMacroName;
    if (ref $sMacro) {
        return {
            DATA => [ $sMacro ],
            ERROR => "'$sMacroName' is an object.",
        };
    }
    my $aMacro= $self->splitValue(
        $fPreParse->(
            $self->remove_backslashes_part1($sMacro)
        )
    );
    my $aNewMacroStack= [ "${sMacroPath}[$sMacroName]" ];
# print "Macro: $sMacro\n";
    $sResult{DATA}= $fExpand->($aMacro, $oMacroScope, $aNewMacroStack);
    push @$aMacroStack, $aNewMacroStack;
# print "Done $sMacroName\n";
    return \%sResult;
}

sub resolveObjects {
    my $self= shift;
    my $sProperty= shift;
    my $aStack= shift || [];
    
    return map {$self->remove_backslashes_part2($_)} @{$self->_resolveObjects(["&$sProperty"], $self, $aStack)};
}

sub _resolveObjects {
    my $self= shift;
    my $aValue= shift;
    my $oScope= shift || $self;
    my $aStack= shift || [];

    my @oResult= ();
    
    for my $sValue (@$aValue) {

        # if value is a single macro simply resolve it
        if ($sValue=~ s/^\&($sregIdentRef)$/$1/) {

            # macros are expanded and result added to @oResult

# print "expanding macro: '$sValue'\n";
# print "scope: ", $self->get_full_name() , "\n";

            my $hResult = $self->expandMacro($sValue, $oScope, $aStack, sub{$self->_resolveObjects(@_)});
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
            next;
        }
        
        # if value is a scalar
        # expand all contained macros
        my $f = sub {
            my $sName= shift;
            my $sResult= $self->joinValue(
                $self->_resolveObjects(["&$sName"], $oScope, $aStack)
            );
            return $sResult if defined $sResult;
            logger->warn("Could not resolve '&$sName'");
            return '';
        };
        while (
            $sValue=~ s/(?<!\\)\&($sregIdentRef)/$f->($1)/ge ||
            $sValue=~ s/(?<!\\)\&\{($sregIdentRef)\}/$f->($1)/ge
        ) {}
        logger->warn("Unescaped '&' in '$sValue'") if $sValue=~ /(?<!\\)\&/;

        # ...and push scalar
        push @oResult, $sValue;
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

sub get_all_references {
    my $self= shift;
    my $aMacroStack= shift;
    
    my @aStack= @$aMacroStack;
    return () unless scalar @aStack;
    my $sMacroPath= shift @aStack;
    return () unless $sMacroPath =~ /\[([^\[\]]*)\]$/;
    my @sResult= ($1);

    while (my $aSubStack= shift @aStack) {
        push @sResult, $self->get_all_references($aSubStack);
    }
    return @sResult;
}

sub showUncachedReferences {
    my $self= shift;
    my $aMacroStack= shift;

    my @sResult= ();
    while (1) {

        # show all referenced objects not already shown and not anonymous
        my @sReferences= grep {
            !defined $aMacroStack->{$_} && !/\.\*\d+$/
        } $self->get_all_references($aMacroStack->{'.'});
        
        last unless scalar @sReferences;
        
        push @sResult, $self->showConfValue($_, $aMacroStack) for (@sReferences);
    }
    
    return @{$self->simplifyShow(\@sResult)};
}

sub getName {
    my $self= shift;
    return $self->get_value('name', '');
}

sub getShowName {
    my $self= shift;
    my $sName= $self->{NAME};
    $sName=~ s/^\*(\d+)/anonymous \($1\)/;
    return $sName;
}

sub showConfValue {
    my $self= shift;
    my $sKey= shift;
    my $hConfShowCache= shift || {};

    return () if defined $hConfShowCache->{$sKey};
    $hConfShowCache->{"$sKey"}= 1;
    # get the original config entry
    my $sValue= $self->get_raw_value("/$sKey");
    return () unless defined $sValue;

    my @sResult= split /\n/, $sValue;
    $sKey.= " = " . (scalar @sResult ? shift @sResult : '');
    return ($sKey, map {"\t$_"} @sResult);
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    my $sKey= $self->get_full_name();

    return [] if $sKey=~ /\*\d*$/; # don't show anonymous objects

    my $bKeyInvalid= 1;    
    my @sResult= ();

    $hConfShowCache->{'.'}= [] unless $hConfShowCache->{'.'};

    for my $sSubKey ($self->sort_show_keys(keys %{ $self->{VALUES} })) {
        next if $sSubKey =~ /^\./;
        if (ref($self->{VALUES}{$sSubKey})) {

            # remember referenced objects for later showing
            $self->{VALUES}{$sSubKey}->show({'.' => $hConfShowCache->{'.'}});
            next;
        }

        # to get all references (objects will not change $hReferences and should be handled later)
        $self->get_value($sSubKey, undef,  $hConfShowCache->{'.'});
        push @sResult, $self->showConfValue("$sKey.$sSubKey", $hConfShowCache);
    }
    push @sResult, "[]" unless $bKeyInvalid;
    return \@sResult;
}

sub simplifyShow {
    my $self= shift;
    my $sOrig= shift;
    my @sResult = ();
    
#print Dumper($sOrig);
#return $sOrig;

    my $sScope= "";
    my $sOrigScope= "";
    for my $sLine (@$sOrig) {
        if ($sLine =~ /^[\#\s]/ || $sLine eq '') {
            push @sResult, $sLine;
            next;
        }
        if ($sLine =~ /^\[\s*(\S*)\s*\]$/) {
            $sOrigScope= $1;
            $sOrigScope.= '.' unless $sOrigScope eq '';
            next;
        }
        $sLine= "$sOrigScope$sLine";
        my $sNewScope= $sLine =~ s/^($sregIdentDef)\.// ? $1 : "";
        if ($sNewScope ne $sScope) {
            $sScope= $sNewScope;
            # do not insert empty line if last was already empty
            push @sResult, "" if scalar @sResult && $sResult[-1] ne '';
            push @sResult, "[$sScope]";
        }
        push @sResult, $sLine;
    }

    # Always add a []. Will be removed by top level caller.
    push @sResult, "[]";
    ## push @sResult, "[]" unless $sScope eq '';
    return \@sResult;
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
