#!/usr/bin/perl

package Rabak::ConfFile;

use warnings;
use strict;
no warnings 'redefine';

use Rabak::Conf;
use Rabak::Log;

use Rabak::Job;      # benoetigt in printJobList

use Term::ANSIColor;

use Data::Dumper;
use Storable qw(dclone);

=pod

=head1 NAME

Rabak::ConfFile - Read Conf Files

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
    my @sFiles= grep {defined $_} @_;

    @sFiles = (
        "$ENV{HOME}/.rabak/rabak.cf",
        "/etc/rabak/rabak.cf",
        "/etc/rabak.cf",
        "./rabak.cf",
    ) unless @sFiles;

    my $self= {
        FILE => '',
        SEARCHPATHS => [ map { /(.*)\/[^\/]+$/ ? $1 : '.' } grep { defined } @sFiles ],
        CONF => Rabak::Conf->new('*'),
    };
    bless $self, $class;
    
    # find first existing file
    my $sFile= (grep { defined && -f } @sFiles)[0];

    if (!defined $sFile && scalar @sFiles) {
        logger->error("No configuration found in '"
            . join("', '", grep(defined, @sFiles))
            . "'!");
        return $self;
    }

    $self->readFile($sFile) if $sFile;
    return $self;
}

#define some regexp
our $sregIdent= Rabak::Conf->REGIDENT;
our $sregIdentDef= Rabak::Conf->REGIDENTDEF;
our $sregIdentRef= Rabak::Conf->REGIDENTREF;

sub filename {
    my $self= shift;
    return $self->{FILE};
}

sub conf {
    my $self= shift;
    return $self->{CONF};
}

=item printJobList

Prints a list of available jobs.

=cut

sub printJobList {
    my $self= shift;
    
    return unless defined $self->filename();

    my $bFound= 0;
    my $oConf= $self->{CONF};
    for my $oJob (Rabak::Job->GetJobs($oConf)) {
        my $oTarget= $oJob->getTargetPeer(); 
        my @oSources= $oJob->getSourcePeers();
        next unless $oTarget && scalar @oSources;

        my @aSources= ();
        for (@oSources) {
            push @aSources, $_->getFullPath();
        }
        my $sSources= join '", "', @aSources;
        logger->print('  ' . colored($oJob->getFullName(), 'bold') . ' - ' . $oJob->getValue("title")
            . ", backs up \"$sSources\" to \""
            . $oTarget->getFullPath() . "\"");
        $bFound= 1;
    }
    logger->print("None.") unless $bFound;
}

=item printAll

Prints the complete, parsed configuration.

=cut

sub printAll {
    my $self= shift;

    my $hConfShowCache= {};
    $self->{CONF}->show($hConfShowCache);

    my @sResult= (
        "# These are the resulting values of \"" . $self->filename() . "\":",
        "# (Btw, this output may be used as a valid configuration file.)",
        "",
    );

    push @sResult, $self->{CONF}->showUncachedReferences($hConfShowCache);
    # pop last "[]"
    pop @sResult;
    logger->print(@sResult);
}

sub _error {
    my $self= shift;
    my ($sMsg, $sFile, $iLine, $sLine)= @_;

    my $sError= "file \"$sFile\"";
    $sError .= ", line $iLine" if $iLine;
    $sError .= ": $sMsg.";
    $sError .= " ($sLine)" if $sLine;
    logger->error($sError);
    exit 3;
}

sub readFile {
    my $self= shift;

    # use absolute paths only (needed for includes)
    my $sFile= Cwd::abs_path(shift);
    $self->{CONF}= Rabak::Conf->new('*');
    # $self->{CONF}= Rabak::Conf->new($sFile);
    $self->{FILE}= $sFile;
    $self->_readFile($sFile);
}

sub _readFile {
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

    my $oConf= $self->{CONF};
    my $sName= undef;
    my $iLine= 0;
    my $sPrefix= '';
    while (my $sLine= <$fin>) {
        $iLine++;
        next if $sLine =~ /^#/;

        $sLine =~ s/(?<!\\)\s+$//;
        next if $sLine eq '';

        last if $sLine =~ /^END$/;
        
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
            $self->_readFile($sInclude, $sFile, $iLine);
            next;
        }

        if ($sLine =~ /^\[\s*\]$/) {
            $sPrefix= '';
            next ;
        }
        if ($sLine =~ /^\[\s*($sregIdentDef)\s*\]$/) {
            $sPrefix= "$1.";
            next;
        }

        my $bIndent= $sLine =~ s/^\s+//;

        my $sValue;
        if ($bIndent) {
            $self->_error("Unexpected value", $sFile, $iLine, $sLine) unless defined $sName;
            $sValue= $sLine;
        }
        else {
            my $sPrefLine= "$sPrefix$sLine";
            $self->_error("Syntax error", $sFile, $iLine, $sLine) unless $sPrefLine =~ s/^($sregIdentDef)\s*=\s*//i;
            $sName= lc $1;
            $sValue= $sPrefLine;
        }

        # get previous value and best matching scope
        my ($sOldValue, $oScope)= $oConf->getProperty($sName);
        my $sNewValue= $sValue;

        # In case of a multiline, we need a newline at the end of each line
        if ($bIndent) {
            $sNewValue= defined $sOldValue ? $sOldValue : '';
            $sNewValue=~ s/\n?$/\n/;

            # escape '$' to prevent warning later (will be removed in last step)
            $sNewValue=~ s/\$/\\\$/g;
            $sNewValue.= "$sValue\n";
        }

        $sNewValue= $self->_removeQuotes($sNewValue);

        # remove current key to prevent self referencing
        $oConf->removeProperty($sName);
        if ($sNewValue=~ /^\$($sregIdentRef)$/ || $sNewValue=~ /^\$\{($sregIdentRef)\}$/) {

            # if value is a simple reference, replace it by reference's content (may be an object)
            my $sRef= $1;
            $sNewValue= $oScope->findProperty($sRef);
            $self->_error("Could not resolve symbol '\$$sRef'", $sFile, $iLine, $sLine) unless defined $sNewValue;
            if (ref $sNewValue) {

                # objects should be cloned to new location
                my $sqNewValuesName= quotemeta $sNewValue->getFullName();
                $self->_error("Could not reference parent", $sFile, $iLine, $sLine) if $sName=~ /^$sqNewValuesName\./;

                # preset value to create all parent objects
                $oConf->setValue($sName, '');
                my (undef, $oNewScope, $sLastKey)= $oConf->getProperty($sName);

                # create new conf-object
                my $new= Rabak::Conf->new($sLastKey, $oNewScope);

                # and clone all values
                $new->{VALUES}= dclone($sNewValue->{VALUES});
                $sNewValue= $new;
            }
        }
        else {

            # function to expand referenced macros as scalar
            my $f = sub {
                my $sRef= shift;
                my $sResult= $oScope->findProperty($sRef);
                $self->_error("Could not resolve symbol '$sRef'", $sFile, $iLine, $sLine) unless defined $sResult;
                $self->_error("'$sRef' is an object", $sFile, $iLine, $sLine) if ref $sResult;

                # escape '$' to prevent warning later (will be removed in last step)
                $sResult=~ s/\$/\\\$/g if $sResult && ! ref $sResult;
                return $sResult;
            };

            # replace every occurance of a reference with reference's scalar value (or raise an error)
            $sNewValue= Rabak::Conf::MarkBackslashes($sNewValue);
            while (
                $sNewValue=~ s/(?<!\\)\$($sregIdentRef)/$f->($1)/ge ||
                $sNewValue=~ s/(?<!\\)\$\{($sregIdentRef)\}/$f->($1)/ge
            ) {};
            logger->warn("Unescaped '\$' in file '$sFile', line $iLine ($sLine)") if $sNewValue=~ s/(?<!\\)\$/\\\$/g;
            # TODO: what to do with multi line quotes?
            logger->warn("Unescaped '\"' in file '$sFile', line $iLine ($sLine)") if $sNewValue=~ s/(?<!\\)\"/\\\"/g;
            logger->warn("Unescaped \"'\" in file '$sFile', line $iLine ($sLine)") if $sNewValue=~ s/(?<!\\)\'/\\\'/g;
            $sNewValue= Rabak::Conf::SweepBackslashes($sNewValue);
        }
        $oConf->setValue($sName, $sNewValue);
    }

    return $oConf;
}

sub _removeQuotes {
    my $self= shift;
    my $sValue= shift;

    # unquote quoted parts (precede \s, "\" and "," with "\" if inside quotes)
    my $unquote= sub {
        my $qchar= shift;
        my $quote= shift;

        $quote =~ s/\~/\.\~/g;
        $quote =~ s/\\/\\\~/g;
        # escape all occurances of \s, ",", "(" and ")"
        $quote =~ s/([\s\,\(\)])/\\$1/g;

        # escape all occurances of "$" and "&" for single quotes
        # escape all occurances of other quote char for both
        # (all occurances of $qchar are exscaped already)
        $quote =~ s/([\$\&\"])/\\$1/g if $qchar eq "'";
        $quote =~ s/([\'])/\\$1/g if $qchar eq '"';
        $quote =~ s/\\\~/\\/g;
        $quote =~ s/\.\~/\~/g;
        return $quote;
    };
#    $sValue =~ s/^(.*?)(?<!\\)([\'\"])(.*?)(?<!\\)\2/$1 .$unquote->($2, $3)/egs; # ?; # for correct highlighting
    $sValue =~ s/(?<!\\)([\'\"])(.*?)(?<!\\)\1/$unquote->($1, $2)/egs;
    return $sValue;
}

1;
