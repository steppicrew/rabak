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
    my $oTargetPath= $self->get_targetPath;
    my $sRsyncPass= $oTargetPath->get_value("passwd");
    my $sPort= $oTargetPath->get_value("port") || 22;

    my $sSrc= $self->valid_source_dir() or return 3;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->tempfile();
    my ($fhwPass, $sPassFile);

    my $sInclude= $self->get_value('include') || '';
    my $sExclude= $self->get_value('exclude') || '';

    my $hIncExc= {};

    for (split(/,\s+|\n/, $sExclude)) {
        s/^\s+//;
        s/\s+$//;
        # $_= "/*" if $_ eq "/";
        $self->build_dirhash($_, '-', $hIncExc) if $_;
    }

    for (split(/,\s+|\n/, $sInclude)) {
        s/^\s+//;
        s/\s+$//;

        # rsync works top down, so include all containing directories:
#        if (/^\/(.+\/)/) {
 #           my @sDir= split(/\//, $1);
  #          my $sDir= "/";
   #         for my $i (0 .. $#sDir) {
    #            $sDir .= $sDir[$i] . "/";
     #           print $fhwRules "+ $sDir\n";
      #      }
#        # }

        # let all directories end with /** to include subdirectories
        $_ .= '*' if /\/\*$/;
        $_ .= '**' if /\/$/;

        $self->build_dirhash($_, '+', $hIncExc);
    }

    print $self->unfold_dirhash($hIncExc); die;

    print $fhwRules "- /**\n" if $sInclude;

    close $fhwRules;

    # print `cat $sRulesFile`;

    my $sFlags= "-a"
        . " --hard-links"
        . " --filter=\". $sRulesFile\""
        . " --stats"
        . " --verbose"
    ;

    $sFlags .= " -i" if $self->{DEBUG};
    $sFlags .= " --dry-run" if $self->get_value('switch.pretend');
    $sFlags .= " $sRsyncOpts" if $sRsyncOpts;
    $sFlags .= " -e 'ssh -p $sPort'" if $oTargetPath->remote;
    if ($oTargetPath->remote && $sRsyncPass) {
        ($fhwPass, $sPassFile)= $self->tempfile();
        print $fhwPass $sRsyncPass;
        close $fhwPass;
        $sFlags .= " --password-file=\"$sPassFile\""
    }

    my $iScanBakDirs= $self->get_value('scan_bak_dirs', 4);

    splice @sBakDir, $iScanBakDirs if $#sBakDir >= $iScanBakDirs;
    map { $sFlags .= " --link-dest=\"$_\""; } @sBakDir;

    $sSrc .= "/" unless $sSrc =~ /\/$/;
    my $sDestDir= $oTargetPath->getPath($self->get_value("full_target"));
    if ($oTargetPath->remote) {
        $sDestDir= $oTargetPath->get_value("host") . ":$sDestDir";
        $sDestDir= $oTargetPath->get_value("user") . "\@$sDestDir" if $oTargetPath->get_value("user");
    }

    my $sRsyncCmd= "rsync $sFlags \"$sSrc\" \"$sDestDir\"";

    $self->log($self->infoMsg("Running: $sRsyncCmd"));

    # print Dumper($self); die;

    my @sRsyncStat= grep !/^([^\/]+\/)+$/, `$sRsyncCmd 2>&1`;

    if ($?) {
        $self->log($self->errorMsg(@sRsyncStat));
        return 1;
    }

    my @sRsyncFiles= ();
    push @sRsyncFiles, shift @sRsyncStat while ($sRsyncStat[0] && $sRsyncStat[0] !~ /^\s+$/);
    push @sRsyncFiles, shift @sRsyncStat;

    $self->log([ 3, @sRsyncFiles ]);
    $self->log(@sRsyncStat);

    return 0;
}

sub build_dirhash {
    my $self= shift;
    my $sFile= shift;
    my $sFilter= shift;
    my $hDirHash= shift || { };

    if ($sFile =~ s/^([^\/]*)\///) {
        my $sDirPart= $1;
        $hDirHash->{$sDirPart}{SUBDIR}= $self->build_dirhash($sFile, $sFilter, $hDirHash->{$sDirPart}{SUBDIR});
    }
    else {
        $hDirHash->{$sFile}= { FILTER => $sFilter };
    }
    return $hDirHash
}

sub unfold_dirhash {
    my $self= shift;
    my $hDirHash= shift;
    my $sBaseDir= shift || '';


    my $sResult= '';
    my @Dirs= sort keys(%$hDirHash);
    my @Dirs2= ();
    my @sortedDirs= ();
    my @StarStarDirs= ();
    my @StarDirs= ();
    my $bThisDir= 0;

    if (@Dirs && $Dirs[0] eq '') {
        $bThisDir= 1;
        shift @Dirs;
    }
#    map {
#            if (/\*\*/) {
#                push @StarStarDirs, $_;
#            }
#            else {
#                push @Dirs2, $_;
#            }
#        } @Dirs;
#    @Dirs= ();
#    map {
#            if (/\*/) {
#                push @StarDirs, $_;
#            }
#            else {
#                push @Dirs, $_;
#            }
#        } @Dirs2;
    for (my $i=$#Dirs; $i >= 0; $i--) {
        my $sDir= shift @Dirs;
        if ($sDir =~ /\*\*/) {
            push @StarStarDirs, $sDir;
        }
        elsif ($sDir =~ /\*/) {
            push @StarDirs, $sDir;
        }
        else {
            push @Dirs, $sDir;
        }
    }
    push @sortedDirs, @Dirs, @StarDirs, @StarStarDirs;
    push @sortedDirs, '' if $bThisDir;
#print Dumper(@sortedDirs); die;
    foreach my $sDir (@sortedDirs) {
        $sResult.= $self->unfold_dirhash($hDirHash->{$sDir}{SUBDIR}, "$sBaseDir$sDir/") if $hDirHash->{$sDir}{SUBDIR};
        $sResult.= "$hDirHash->{$sDir}{FILTER} $sBaseDir$sDir\n" if $hDirHash->{$sDir}{FILTER};
    }
    return $sResult;
}

1;

