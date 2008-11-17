
package RabakLib::Version;

use Exporter;
use vars(@ISA);
use Term::ANSIColor;

@ISA= qw( Exporter );
@EXPORT= qw( &VERSION );

sub VERSION { "1.0" }

sub VersionMsg {
    return "\n" . colored("This is Rabak, version " . VERSION(), 'bold') . "\nRabak is your powerful and reliable rsync based backup system.\n";
}

sub LongVersionMsg {
    return VersionMsg() .
"$version
Copyright 2007-2008, Stephan Hantigk & Dietrich Raisin

Rabak may be copied only under the terms of either the Artistic License or the
GNU General Public License, which may be found in the Perl 5 source kit.
";

# Complete documentation for Perl, including FAQ lists, should be found on
# this system using "man perl" or "perldoc perl".  If you have access to the
# Internet, point your browser at http://www.perl.org/, the Perl Home Page.

}

1;
