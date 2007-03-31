#!/usr/bin/perl

package RabakLib::Type::File;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

use Data::Dumper;

sub run {
    my $self= shift;
    my @sBakDir= @_;

    # print Dumper($self); die;

    # print '**'.$self->get_value('switch.pretend').'**'; die;

    my $sBakSet= $self->get_value('name');
    my $sRsyncOpts = $self->get_value('rsync_opts') || '';

    my $sSrc= $self->valid_source_dir() or return 3;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->tempfile();

    my $sInclude= $self->get_value('include') || '';
    my $sExclude= $self->get_value('exclude') || '';

    $sExclude= "*" if $sExclude eq '' && $sInclude ne '';

    for (split(/,\s+|\n/, $sInclude)) {
        s/^\s+//;
        s/\s+$//;
	
	# rsync works top down, so include all containing directories:
	if (/\//) {
	    my @sDir= split(/\//);
	    my $sDir= "";
    	    for my $i (1 .. $#sDir - 1) {
		$sDir .= "/".$sDir[$i];
	        print $fhwRules "+ $sDir/\n";
	    }
	}

	# let all directories end with /** to include subdirectories
	$_ .= '*' if /\/\*$/;
	$_ .= '**' if /\/$/;

        print $fhwRules "+ $_\n" if $_;
    }

    for (split(/,\s+|\n/, $sExclude)) {
        s/^\s+//;
        s/\s+$//;
	# $_= "/*" if $_ eq "/";
        print $fhwRules "- $_\n" if $_;
    }

    close $fhwRules;

    my $sFlags= "-a"
        . " -v --stats --hard-links"
        . " --filter=\". $sRulesFile\""
    ;

    $sFlags .= " --verbose -i" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $self->get_value('switch.pretend');
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    $sSrc .= "/" unless $sSrc =~ /\/$/;
    my $sDestDir= $self->get_value('full_target');

    my $sRsyncCmd= "rsync $sFlags \"$sSrc\" \"$sDestDir\"";

    $self->xlog("Running: $sRsyncCmd");

    # print Dumper($self); die;

    @_= grep !/^([^\/]+\/)+$/, `$sRsyncCmd 2>&1`;
    $self->xlog(join('', @_));

    return 0;
}

1;

