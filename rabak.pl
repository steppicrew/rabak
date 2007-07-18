#!/usr/bin/perl

# wrapper for backward compatibility
my $scriptname=`basename "$0" ".pl"`;
my $dirname=`dirname "$0"`;
chomp $scriptname;
chomp $dirname;

print "WARNING: please use '$dirname/$scriptname'!\n";
print "calling $0 is deprecated!\n";

exec "$dirname/$scriptname", @ARGV;
