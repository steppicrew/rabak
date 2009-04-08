#!/usr/bin/perl

package Rabak::Wui;

use strict;
use warnings;

use lib "../../../lib";

use Rabak;
use Data::Dumper;
use JSON::XS;

my %dispatch= (
    '/' => \&_Index,
    '/index' => \&_Index,
    '/api' => \&_Api,
);

sub Request {
    my $path= shift;
    my $params= shift;

#    print "Requested: [$path]\n";

    my $handler = $dispatch{$path};
    return $handler->($params) if ref($handler) eq "CODE";
    return undef;
}

#    return "<pre>$path"
#        . Dumper($params)
#        . "<form method=post action=/huhu ><input name=x /><textarea name=y></textarea></form>"
#    ;
#    return "Not found";
#}

sub _Api {
    my $params= shift;
    return encode_json(Rabak::API($params));
}

sub _Index {
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
    <script language="javascript" src="/static/wui.js"></script>
</head>
<body>
    Loading...
</body>
</html>
EOT
}

1;
