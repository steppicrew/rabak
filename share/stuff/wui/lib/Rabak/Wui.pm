#!/usr/bin/perl

package Rabak::Wui;

=head1 NAME

Rabak Web User Interface (aka Rabak WUI)

=head1 DESCRIPTION

Rabak WUI allows monitoring of Rabak processes from a web browser. It features
session handling and fancy graphics.

This package contains the request handler for Web requests. These are typically
made by C<wui>, a HTTP server that comes with Rabak.

=cut

use strict;
use warnings;

use lib "../../../lib";

use Rabak;
use Rabak::ConfFile;

use Data::Dumper;
use JSON::XS;

our $oConf;

our $aGroups;
our $aUsers;
our $aConfs;

our %aSessions;

=head1 METHODS

=head2 Class Methods

=over 4

=item C<Request>

    Request($path, $params)

    Request("/login", { usr => "john", "pw" => "doe" })

Handles a request. C<$path> is dispached to a corresponding method,
which receives C<$params>.

If successful, returns a string containing the information for the
client.

Returns C<undef> on failure.

=cut

sub Request {
    my $path= shift;
    my $params= shift;

    _readConf() unless $oConf;

    my $handler = $dispatch{$path};
    return undef unless ref($handler) eq "CODE";

    return $handler->($params);
}


# Reads config file for Web UI
sub _readConf {
    my $oConfFile= new Rabak::ConfFile("wui.cf");
        
    # FIXME: Wie feststellen dass Load nicht geklappt hat?
    # $oConf->print_all();

    $oConf= $oConfFile->conf();
        
    # print "value:", $oConf->get_value("group"), "\n";
    # print "raw_value:", $oConf->get_raw_value("group"), "\n";
    # print "property:", $oConf->get_property("group"), "\n";
    # print "node:", $oConf->get_node("group"), "\n";
        
    $aGroups= $oConf->get_node("group");
    $aUsers= $oConf->get_node("user");
    $aConfs= $oConf->get_node("conf");

    # FIXME: Fehlerbehandlung!
}

# Fetches a session. The Session-Id is in $params->{sid}. If the session
# is invalid a new one will be generated. If $params->{usr} and $params->{pw}
# are set to a proper value, the user will be logged in for this session.
sub _getSession {
    my $params= shift;

    for (keys %aSessions) {
        delete $aSessions{$_} if $aSessions{$_}{valid_until} < time;
    }

    my $sid;
    my $oUser;
    my $loginError;
    if ($params->{sid} && $aSessions{$params->{sid}}) {
        $sid= $params->{sid};
        $oUser= $aUsers->get_node($aSessions{$sid}{user_name});
    }
    else {
        $sid= '';
        $sid= substr($sid . int(rand(100000)), 0, 12) while length($sid) < 12;
    }

    $aSessions{$sid}= { sid => $sid } unless $oUser;

    if ($params->{usr} || $params->{pw}) {
        $oUser= $aUsers->get_node($params->{usr});
        if (!$oUser) {
            print "Failed to login as '", $params->{usr}, "'. User unknown.\n";
            $loginError= 1;
        }
        elsif ($oUser->get_value("password") ne $params->{pw}) {
            print "Failed to login as '", $params->{usr}, "'. Wrong password.\n";
            $oUser= undef;
            $loginError= 1;
        }
        else {
            $aSessions{$sid}{user_name}= $params->{usr};
        }
    }

    $aSessions{$sid}{valid_until}= time + 3600;  # valid 1 hour from request
    $aSessions{$sid}{user_title}= $oUser ? $oUser->get_value("title") : undef;
    $aSessions{$sid}{login_error}= $loginError;

    return $aSessions{$sid};
}

my %dispatch= (
    '/' => \&_Index,
    '/login' => \&_Login,
    '/logout' => \&_Logout,
    '/index' => \&_Index,
    '/api' => \&_Api,
);

sub _Login {
    my $params= shift;

    my $oSession= _getSession($params);
    return '<meta http-equiv="refresh" content="0; url=/?sid=' . $oSession->{sid}
        . ($oSession->{login_error} ? '&err=1' : '')
        . '">';
}

sub _Logout {
    my $params= shift;

    my $sid= _getSession($params)->{sid};
    delete $aSessions{$sid};
    return '<meta http-equiv="refresh" content="0; url=/">';
}

sub _Api {
    my $params= shift;

    my $oSession= _getSession($params);
    return encode_json(
        $oSession->{user_name} ? Rabak::API($params) : { error => 401, error_text => 'Authorization required' }
    );
}

sub _Index {
    my $params= shift;

    my $oSession= _getSession($params);
    my $sid= $oSession->{sid};
    my $userName= $oSession->{user_name} || '';
    my $userTitle= $oSession->{user_title} || '';
    my $loginError= $params->{err} ? 1 : 0; # untaint
    return <<EOT;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
    <title>Rabak Web UI</title>
    <link rel="stylesheet" type="text/css" href="/static/all.css"></link>
    <script>
        if (typeof console == "undefined") {
            console= { log: function() {}, warn: function() {}, error: function() {} }; // global firebug stub
        }
    </script>
    <script language="javascript" src="/static/jquery-1.3.2.min.js"></script>
    <script language="javascript" src="/static/jquery.flot-0.5.pack.js"></script>
    <script language="javascript" src="/static/wui.js"></script>
    <script>
        var sid= "$sid";
        var userName= "$userName";
        var userTitle= "$userTitle";
        var loginError= $loginError;
    </script>
</head>
<body>
    <div id="head-c"><div id="head"></div></div>
    <div id="sidebar-c"><div id="sidebar"></div></div>
    <div id="body-c"><div id="body"></div></div>
</body>
</html>
EOT
}

=back

=cut

=head1 COPYRIGHT

Copyright (c) 2009 Dietrich Raisin and Stephan Hantigk.
All rights reserved.  This module is free software;
you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
