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

sub get_raw_value {
    my $self= shift;
    my $sName= shift;
    my $sDefault= shift || undef;
    
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

sub remove_backslashes_part2 {
    my $self= shift;
    my $sValue= shift;

    return $sValue unless $sValue;

    # Insert support for tab etc.. here
    # $sValue =~ s/\\t/\t/g;

    # remove all backslashes
    $sValue =~ s/\\(?!_)//g;
    # rereplace changes made in part1
    $sValue =~ s/\\\~/\\/g;
    $sValue =~ s/\.\~/\~/g;
    return $sValue;
}

sub remove_backslashes {
    my $self= shift;
    my $sValue= shift;

    return $self->remove_backslashes_part2($self->remove_backslashes_part1($sValue));
}

sub get_value {
    my $self= shift;
    return $self->remove_backslashes($self->get_raw_value(@_));
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

# returns array of properties contents, resolving referenced objects
# array contains refrences to RabakLib::Conf or scalars
sub resolveObjects {
    my $self= shift;
    my $sProperty= shift;
    my $hStack= shift || {};

    my @oResult= ();

    if ($hStack->{"$self.$sProperty"}) {
        logger->error("Recursive reference to '$sProperty'.");
        return @oResult; 
    }
    $hStack->{"$self.$sProperty"}= 1;
    
    my ($Value, $oOwningConf)= $self->get_property($sProperty); 

    if (defined $Value) {
        if (ref $Value) {
            push @oResult, $Value;
        }
        else {
            my $sValue= $self->remove_backslashes_part1($Value);
            my @sValues= split /(?<!\\)\s+/, $sValue;
            for $sValue (@sValues) {
                if ($sValue=~ s/^\&//) {
                    push @oResult, $oOwningConf->resolveObjects($self->remove_backslashes_part2($sValue), $hStack) if $oOwningConf;
                }
                else {
                    push @oResult, $self->remove_backslashes_part2($sValue);
                }
            }
        }
    }
    else {
        logger->error("Object '$sProperty' could not be loaded. Skipped.");
    }
    delete $hStack->{"$self.$sProperty"};
    return @oResult;
}

sub sort_show_key_order {()}

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
    
    for ($self->sort_show_keys(keys %{ $self->{VALUES} })) {
        next if $_ =~ /^\./;
        if (ref($self->{VALUES}{$_})) {
            # print Dumper($self->{VALUES}{$_}); die;
            $self->{VALUES}{$_}->show($hConfShowCache);
            next;
        }
        my $sValue= $self->get_value($_) || '';
        $sValue =~ s/\n/\n\t/g;
        print "$sKey.$_ = $sValue\n" unless defined $hConfShowCache->{"$sKey.$_"};
        $hConfShowCache->{"$sKey.$_"}= 1;
    }
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
