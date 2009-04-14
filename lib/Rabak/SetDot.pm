#!/usr/bin/perl

package Rabak::SetDot;

use warnings;
use strict;

use Rabak::Set;

# =============================================================================
#  For Sets: Generate Output for dot (graphviz)
#  UNTESTED!
# =============================================================================

sub new {
    my $class= shift;
    my $oSet= shift;

    my $self= {};
    $self->{SET}= $oSet;
    $self->{_BOX_ADDED}= $oSet;
    bless $self, $class;
}

my %_boxAdded;

sub _dotify {
    $_[0] =~ s/"/\\"/g;
    return $_[0];
}

sub _dothtmlify {
    $_[0] =~ s/&/&amp;/g;
    $_[0] =~ s/</&lt;/g;
    $_[0] =~ s/>/&gt;/g;
    return $_[0];
}

sub _dotConfTitle {
    my $sType= shift;
    my $oConf= shift;

	# ->getValue("name") ??
    my $sTitleText= $oConf->{VALUES}{'name'} || $oConf->{NAME};
    $sTitleText= ucfirst($sType) . " \"$sTitleText\"";
    $sTitleText .= ': ' . $oConf->{VALUES}{'title'} if $oConf->{VALUES}{'title'};
    return $sTitleText;
}

sub _dotAddBox {
    my $self= shift;
    my $sType= shift;
    my $oConf= shift;
    my $oParentConf= shift;

    my $sTitleBgColor= '#DDDDDD';
    $sTitleBgColor= '#DDDD00' if $sType eq 'mount';
    $sTitleBgColor= '#00DDDD' if $sType eq 'source';
    $sTitleBgColor= '#DD00DD' if $sType eq 'target';

    my $sAttribs= 'shape="rect"';
    $sAttribs= 'shape="polygon" skew="0.5"' if $sType eq 'mount';
    $sAttribs= 'shape="invhouse"' if $sType eq 'mount';
    $sAttribs= 'shape="rect" style="filled" color="#F0F0E0"' if $sType eq 'mount';

    my %hKeys;
    map { $hKeys{$_}= 1 } keys %{ $oConf->{VALUES} };

    my $sTitleText= _dothtmlify(_dotConfTitle($sType, $oConf));
    $sTitleText= "<table border=\"0\"><tr><td>$sTitleText</td></tr></table>";

    my $sName= $oConf->{NAME};

    my $sResult= '';
    $sResult .= "\"$sName\" [ label=<";
    $sResult .= "<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\">";
    $sResult .= "<tr><td colspan=\"3\" bgcolor=\"$sTitleBgColor\">$sTitleText</td></tr>";
    $sResult .= "<tr><td colspan=\"3\"><font point-size=\"4\">&#160;</font></td></tr>";

    my $_add= sub {
        my $sKey= shift;
        my $sValue;
        if (ref $oConf->{VALUES}{$sKey}) {
            $sValue= '$' . $oConf->{VALUES}{$sKey}{NAME};
        }
        else {
            $sValue= $oConf->{VALUES}{$sKey} || '';
        }
        return if $sValue eq '';
        $sValue= substr($sValue, 0, 27) . "..." if length($sValue) > 30;
        $sResult .= "<tr><td align=\"left\">" . _dothtmlify($sKey) . ":</td><td>&#160;</td><td align=\"left\">" . _dothtmlify($sValue) . "</td></tr>";
        # print Dumper($oSource->{VALUES});

        delete $hKeys{$sKey};
    };

    # force preferred sequence:
    $_add->("name");
    $_add->("type");
    $_add->("path");
    $_add->("user");
    $_add->("password");
    $_add->($_) for sort keys %hKeys;

    $sResult .= "</table>";
    $sResult .= "> $sAttribs ]\n";

    $sResult= "" if $self->{_BOX_ADDED}{$sName};

    $self->{_BOX_ADDED}{$sName}= 1;

    if ($oParentConf) {
        my $sParentName= $oParentConf->{NAME};
        if ($sType eq 'target') {
            $sResult .= "\"$sParentName\" -> \"$sName\"\n";
        }
        else {
            $sResult .= "\"$sName\" -> \"$sParentName\"\n";
        }
    }
    return $sResult;
}

# Build output as graphviz directed graph
#
sub toDot {
    my $self= shift;

    $self->{_BOX_ADDED}= {};

    # print "]\n[";
    # print $self->{SET}->getValue("name");
    # print "]\n[";
    # print $self->{SET}->getValue("title");
    # print "]\n[";

    my @oSources= $self->{SET}->getSourcePeers();

    my $sResult= '';

    $sResult .= $self->_dotAddBox('set', $self->{SET});

    for my $oSource (@oSources) {
        $sResult .= $self->_dotAddBox('source', $oSource, $self->{SET});
    }

    my $oTarget= $self->{SET}->getTargetPeer();
    $sResult .= $self->_dotAddBox('target', $oTarget, $self->{SET});

    my $sTitle= _dotify(_dotConfTitle('set', $self->{SET}));

    $sResult= qq(
        subgraph cluster1 {
            label="$sTitle"
            labelfontsize="18"
            $sResult
        }
    ) if 1;

    for my $oSource (@oSources) {
        for my $oMount ($oSource->getMountObjects()) {
            $sResult .= $self->_dotAddBox('mount', $oMount, $oSource);
        }
    }

    for my $oMount ($oTarget->getMountObjects()) {
        $sResult .= $self->_dotAddBox('mount', $oMount, $oTarget);
    }

    $sResult= qq(
        digraph {
            // rankdir="LR"
            $self->{SET}{NAME} [ shape="rect" ]
            $sResult
        }
    );

    return $sResult;
}

1;
