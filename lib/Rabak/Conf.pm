#!/usr/bin/perl

# TODO: make verbosity levels specifyable in clear text ('error', 'warning', 'info'...)

package Rabak::Conf;

use warnings;
use strict;
no warnings 'redefine';

use Data::Dumper;
use Storable qw(dclone);
use POSIX qw(strftime);
use Rabak::Log;
use Data::UUID;

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
        CMD_DATA=> undef,
    };

    bless $self, $class;
}

# define some regexp
our $sregIdent0= "[a-zA_Z_][a-zA-Z_0-9]*";
our $sregIdent= "$sregIdent0(\\.$sregIdent0)*";
our $sregIdentDef= $sregIdent;
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
        $oValue->{PARENT_CONF}= $new if ref $oValue && $oValue->isa('Rabak::Conf');
    }

    return $new;
}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return ('name');
}

sub setCmdData {
    my $self= shift;
    $self->{CMD_DATA}= shift;
}

# returns cmd data of $sParam (if given) or copy of CMD_DATA
# searches in parent confs if not set via setCmdData
sub cmdData {
    my $self= shift;
    my $sParam= shift;

    return $self->{PARENT_CONF}->cmdData($sParam) if !defined($self->{CMD_DATA}) && defined($self->{PARENT_CONF});
    my $hData= $self->{CMD_DATA} || {};
    return \(%$hData) unless defined $sParam;
    return $hData->{uc $sParam};
}

# Stub to override. A Rabak::Conf is always valid.
sub getValidationMessage {
    return undef;
}

# UNUSED
# sub getValueNames {
#     my $self = shift;
# 
#     return keys %{ $self->{VALUES} };
# }

# Splits a string, using spaces and commas as boundaries.
# FIXME: Is an utility method: remove $self
sub _splitValue {
    my $self = shift;
    my $sValue= shift;
    
    return undef unless defined $sValue;
    
    return [ "" ] if $sValue eq "";
    my @Result = split /(?<!\\)[\s\,]+/, $sValue; # ?; # for correct syntax highlighting
    return \@Result;
}

# Joins array of value parts with spaces.
# Returns undef if there was an object or array is empty.
# FIXME: Is an utility method: remove $self
# FIXME: $bError is superfluous
sub _joinValue {
    my $self = shift;
    my $aValue= shift;
    
    return undef unless defined $aValue;
    
    my $bError;
    my @sValues = map {
        if (ref eq "ARRAY") {
            my $sJoined= $self->_joinValue($_);
            $bError = 1 unless defined $sJoined;
            $sJoined;
        }
        elsif (ref) {
            $bError= 1;
        }
        else {
            # removeBackslashesPart2 should already have been called
#            $self->removeBackslashesPart2($_);
            $_;
        }
    } @$aValue;
    return undef if $bError;
    return undef unless scalar @sValues;
    return join " ", @sValues;
}

# gets array ref of preparsed value, separated by whitespaces
# UNUSED! kill after Juli 09
# sub get_prep_value {
#     my $self= shift;
#     my $sName= shift;
#     my $sDefault= shift;
#     
#     return $self->_splitValue(
#         $self->removeBackslashesPart1(
#             $self->getRawValue($sName, $sDefault)
#         )
#     );
# }

# gets value as written in config
sub getRawValue {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    
    my $sValue= $self->findProperty($sName);
    
    unless (defined $sValue) {
        return $self->{NAME} if lc($sName) eq 'name';      
        return $sDefault;
    }
    return $sDefault if ref $sValue;
    return $sDefault if $sValue eq '*default*';
    return $sValue;
}

sub removeBackslashesPart1 {
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

sub undoRemoveBackslashesPart1 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless defined $sValue;
    return $sValue if ref $sValue;

    $sValue =~ s/\\\~/\\\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
}

sub removeBackslashesPart2 {
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

# DETECTED UNUSED: removeBackslashes
sub removeBackslashes {
    my $self= shift;
    my $sValue= shift;

    return $self->removeBackslashesPart2($self->removeBackslashesPart1($sValue));
}

sub QuoteValue {
    my $self= shift;
    my $sValue= shift;
    return $sValue unless $sValue=~ /[\s\,\'\"]/;
    $sValue=~ s/\\/\\\\/g;
    $sValue=~ s/\'/\\\'/g;
    return "'$sValue'";
}

# returns scalar value (references to other objects are already resolved, backslashes are cleaned)
sub getValue {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    my $aRefStack= shift;
    
    my @sValues= $self->resolveObjects($sName, $aRefStack);
    my $sValue= $self->_joinValue(\@sValues);
    unless (defined $sValue) {
        return $self->{NAME} if lc($sName) eq 'name';      
        return $sDefault;
    }
    return $sDefault if ref $sValue;
    return $sDefault if $sValue eq '*default*';
    return $sValue;
}

# TODO: Which is correct: findProperty? getValue? get_prep_value? $oCOnf->{VALUES}?
sub getValueRequiredMessage {
    my $self= shift;
    my $sField= shift;

    return "Required value \"" . $self->{NAME} . ".$sField\" missing." unless defined $self->findProperty($sField);
    return undef;
}

# command line switches are set in /*.switch
# if not it's a simple property value
sub getSwitch {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift;
    my $aRefStack= shift;
    
    # lookup in /*.-scope is done by findProperty
#    my $sResult= $self->getValue("/*.switch.$sName", undef, $aRefStack);
#    return $sResult if defined $sResult;
    return $self->getValue("switch.$sName", $sDefault, $aRefStack);
}

# find property and return it as it is (scalar, object etc.)
sub findProperty {
    my $self= shift;
    my $sName= shift;
 
    return undef unless defined $sName;

    # first look in '*'-scope
    unless ($sName =~ /\*/) {
        my $sStarName= $sName;
        $sStarName=~ s/^[\.\/]*//;

        # search for existing values in '/*'-scope ('*.zuppi' overwrites '*.zappi.zuppi')
        my $oRootScope= $self->findScope("/*.$sStarName");
        my @sStarName= split(/\./, $sStarName);
        $sStarName= '';
        while (my $sSubKey= pop @sStarName) {
            $sStarName= ".$sSubKey$sStarName";
            my ($oValue, $oScope, $sKey)= $oRootScope->getProperty("*$sStarName");
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
    
    my $oScope= $self->findScope($sName);
    $sName=~ s/^\/?\.*//;
    
    $sName= lc $sName;

    while (defined $oScope) {
        my ($oProp, $oParentConf, $sKey)= $oScope->getProperty($sName);
        if (defined $oProp) {
            return ($oProp, $oParentConf, $sKey) if wantarray;
            return $oProp;
        }
        $oScope= $oScope->{PARENT_CONF};
    }
    return undef;
}

# finds proper scope
sub findScope {
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
sub getProperty {
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
sub removeProperty {
    my $self= shift;
    my $sName= shift;
    
    my (undef, $oScope, $sKey)= $self->getProperty($sName);
    delete $oScope->{VALUES}{$sKey} if defined $oScope && exists $oScope->{VALUES}{$sKey};
}

sub getNode {
    my $self= shift;
    my $sName= shift;
    
    my $oConf= $self->findProperty($sName);
    return $oConf if ref $oConf;
    return undef;
}

sub presetValues {
    my $self= shift;
    my $hValues= shift;
    for my $sName (keys(%$hValues)) {
        $self->setValue($sName, $hValues->{$sName}) if defined $hValues->{$sName};
    }
}

sub setValue {
    my $self= shift;
    my $sName= lc(shift || '');
    my $sValue= shift;

    # go up one level for each starting "." or go to top level for $sName starting with "/"
    $self= $self->{PARENT_CONF} while $self->{PARENT_CONF} && ($sName=~ s/^\.// || $sName=~ /^\//);
    $sName=~ s/^[\.\/]+//;

    my @sName= split(/\./, $sName);
    $sName= pop @sName;
    for my $sSubName (@sName) {
        $self->{VALUES}{$sSubName}= Rabak::Conf->new($sSubName, $self) unless exists $self->{VALUES}{$sSubName};
        unless (ref $self->{VALUES}{$sSubName}) {
            logger->error("'" . $self->getFullName() . ".$sSubName' is not an object!");
            exit 3;
        }
        
        $self= $self->{VALUES}{$sSubName};
    }
    
    # TODO: only allow assignment of undef to refs?
    $sValue->{PARENT_CONF}= $self if ref $sValue && $sValue->isa('Rabak::Conf');
    $self->{VALUES}{$sName}= $sValue;
}

sub setQuotedValue {
    my $self= shift;
    my $sName= shift;
    my $sValue= shift;
    $sValue= $self->QuoteValue($sValue) if $sValue;
    $self->setValue($sName, $sValue);
}

# expand macro given in $sMacroName
# returns array with expanded macro's content
sub _expandMacro {
    my $self= shift;
    my $sMacroName= shift;
    my $oScope= shift || $self;
    my $aStack= shift || [];
    my $bRaiseError= shift;
    my $hResult = $self->expandMacroHash($sMacroName, $oScope, $aStack);  # Remove Juli 09: , sub{$self->_resolveObjects(@_)});
    unless (defined $hResult->{DATA}) {
        logger()->error("$hResult->{ERROR} in scope \""
            . $oScope->getFullName()
            . "\"") if $hResult->{ERROR} && $bRaiseError;
        return ();
    }
# print "got ", Dumper($hResult->{DATA}), "\n";
    return @{$hResult->{DATA}} if ref $hResult->{DATA} eq "ARRAY";
    logger->error(
        "Internal error: _expandMacro(\"$sMacroName\") in scope \""
        . $oScope->getFullName()
        . "\" should return an array reference! (got $hResult->{DATA})",
        "Please file bug report!"
    );
    return ();
}

# expand macro given in $sMacroName
# returns hashref with expanded macro
# calls $fExpand->() for expanding macro's content
# calls $fPrePars->() for preparsing macros content
sub expandMacroHash {
    my $self= shift;
    my $sMacroName= lc shift;
    my $oScope= shift || $self;
    my $aMacroStack= shift || [];
    my $fExpand= shift || sub { $self->_resolveObjects(@_) }; # try to expand macro as deep as possible by default
    my $fPreParse= shift || sub { shift }; # no preparsing by default

    my %sResult= ();

# print "Scope: ", $oScope->getFullName(), "\n";
# print "Expanding $sMacroName\n";

    $sMacroName=~ s/^\&//;
    my ($sMacro, $oMacroScope)= $oScope->findProperty($sMacroName); 
    unless ($oMacroScope) {
        return { ERROR => "Could not resolve Macro \"$sMacroName\"" };
    }
    # build full macro name
    $sMacroName= $oMacroScope->getFullName($sMacroName);

    $aMacroStack->[0] = "[]" unless scalar @$aMacroStack;
    my $sMacroPath= $aMacroStack->[0];
    my $sqMacroName= quotemeta "[$sMacroName]";

    return { ERROR => "Recursion detected (\"$sMacroName\")" } if $sMacroPath=~ /$sqMacroName/;
    return { ERROR => "\"$sMacroName\" does not exist" } unless defined $sMacro;
    $sResult{MACRO}= $sMacroName;
    if (ref $sMacro) {
        return {
            DATA => [ $sMacro ],
            ERROR => "\"$sMacroName\" is an object",
        };
    }
    my $aMacro= $self->_splitValue(
        $fPreParse->(
            $self->removeBackslashesPart1($sMacro)
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
    
    return map { $self->removeBackslashesPart2($_) } $self->_expandMacro($sProperty, $self, $aStack);
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
            push @oResult, $self->_expandMacro($sValue, $oScope, $aStack, 'raise error if macro is not found');
            next;
        }
        
        # if value is a scalar
        # expand all contained macros
        my $f = sub {
            my $sName= shift;
            my $sResult= $self->_joinValue(
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

sub _sortShowKeys {
    my $self= shift;
    my @sKeys= @_;
    
    my @sSortOrder= $self->PropertyNames();
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

sub getAllReferences {
    my $self= shift;
    my $aMacroStack= shift;
    
    my @aStack= @$aMacroStack;
    return () unless scalar @aStack;
    my $sMacroPath= shift @aStack;
    return () unless $sMacroPath =~ /\[([^\[\]]*)\]$/;
    my @sResult= ($1);

    while (my $aSubStack= shift @aStack) {
        push @sResult, $self->getAllReferences($aSubStack);
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
        } $self->getAllReferences($aMacroStack->{'.'});
        
        last unless scalar @sReferences;
        
        push @sResult, $self->showConfValue($_, $aMacroStack) for (@sReferences);
    }
    
    return @{$self->simplifyShow(\@sResult)};
}

sub getName {
    my $self= shift;
    return $self->getValue('name', '');
}

sub setName {
    my $self= shift;
    my $sName= shift;
    $self->{NAME}= $sName;
    return $self->setValue('name', $sName);
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
    
    $sKey=~ s/^\/*\.*//;

    return () if defined $hConfShowCache->{$sKey};
    $hConfShowCache->{"$sKey"}= 1;
    # get the original config entry
    my $sValue= $self->getRawValue("/$sKey");
    return () unless defined $sValue;

    my @sResult= split /\n/, $sValue;
    $sKey.= " = " . (scalar @sResult ? shift @sResult : '');
    return ($sKey, map {"\t$_"} @sResult);
}

sub show {
    my $self= shift;
    my $hConfShowCache= shift || {};
    
    my $sKey= $self->getFullName();

    return [] if $sKey=~ /\*\d*$/; # don't show anonymous objects

    my $bKeyInvalid= 1;    
    my @sResult= ();

    $hConfShowCache->{'.'}= [] unless $hConfShowCache->{'.'};

    for my $sSubKey ($self->_sortShowKeys(keys %{ $self->{VALUES} })) {
        next if $sSubKey =~ /^\./;
        if (ref($self->{VALUES}{$sSubKey})) {

            # remember referenced objects for later showing
            $self->{VALUES}{$sSubKey}->show({'.' => $hConfShowCache->{'.'}});
            next;
        }

        # to get all references (objects will not change $hReferences and should be handled later)
        $self->getValue($sSubKey, undef,  $hConfShowCache->{'.'});
        push @sResult, $self->showConfValue("$sKey.$sSubKey", $hConfShowCache);
    }
    # try to resolve all properties not defined in current object
    for my $sSubKey ($self->PropertyNames()) {
        next if $self->{VALUES}{$sSubKey};
        $self->getValue($sSubKey, undef,  $hConfShowCache->{'.'});
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

sub GetTimeString {
    return strftime("%Y%m%d%H%M%S", gmtime);
}

sub CreateUuid {
    return Data::UUID->new()->create_str();
}

sub getFullName {
    my $self= shift;
    my $sName= shift || '';
    
    $sName=~ s/^\/*//;
    $sName=~ s/^.*\.//;
    while ($self->{PARENT_CONF}) {
        $sName= "$self->{NAME}.$sName";
        $self= $self->{PARENT_CONF};
    }
    $sName=~ s/\.$//;
    return $sName;
}

sub writeToFile {
    my $self= shift;
    my $sFileName= shift;
    
    my $hConfShowCache= {};
    
    my $aConf= $self->show($hConfShowCache);
    push @$aConf, $self->showUncachedReferences($hConfShowCache);
    my @sConf= @ { $self->simplifyShow($aConf) };

    pop @sConf;  # remove last []. (See RabalLib::Conf::show)
    my $fh;
    unless (open $fh, '>', $sFileName) {
        logger->error("Could not open conf file '$sFileName' for writing!");
        return 1;
    }
    print $fh join "\n", @sConf, '';
    close $fh;
}

1;
