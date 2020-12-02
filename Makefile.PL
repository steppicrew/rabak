use 5.008008;
use ExtUtils::Manifest qw( mkmanifest );
use ExtUtils::MakeMaker;
use FindBin qw/ $RealBin /;
use lib $RealBin;
require "lib/Rabak/Version.pm";

mkmanifest();

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'rabak',
    VERSION           => Rabak::Version::VERSION(),
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (AUTHOR         => 'Dietrich Raisin & Stephan Hantigk <rabak@runlevel3.de>') : ()),
);
