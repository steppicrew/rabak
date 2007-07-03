#!/usr/bin/perl

package RabakLib::Type::File;

use warnings;
use strict;
use vars qw(@ISA);
use RabakLib::Type;

@ISA = qw(RabakLib::Type);

use Data::Dumper;
use File::Spec;

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
    my $sTimeout= $oTargetPath->get_value("timeout") || 150;
    my $sBandwidth= $oTargetPath->get_value("bandwidth") || 0;

    my $sSrc= $self->valid_source_dir() or return 3;

    # Write filter rules to temp file:
    my ($fhwRules, $sRulesFile)= $self->tempfile();
    my ($fhwPass, $sPassFile);

    my %sFilter= (
        "+" => $self->get_value('include') || '',
        "-" => $self->get_value('exclude') || '',
    );
    my $hIncExc= {};

    for my $sFilter (keys %sFilter) {
        for (split(/,\s+|\n/, $sFilter{$sFilter})) {
            s/^\s+//; # strip whitespaces
            s/\s+$//;
            s/\/\**$/\/\*\*/; # directories should end with "/**"
            # $_= "/**/$_" unless /^\//; # TODO: is this wise??? may be it should be set by the user to place entry at list's end
            $self->build_dirhash(File::Spec->canonpath($_), $sFilter, $hIncExc) if $_;
        }
    }

    # print $self->unfold_dirhash($hIncExc, {FILES => 1});
    # print $self->unfold_dirhash($hIncExc, {DIRS  => 1}); die;
    print $fhwRules $self->unfold_dirhash($hIncExc, {FILES => 1});
    print $fhwRules $self->unfold_dirhash($hIncExc, {DIRS  => 1});

    # TODO: do we need this???
    # may be we should leave it to the user to add "/"?
#    print $fhwRules "- /**\n" if $sInclude;

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
    if ($oTargetPath->remote) {
        $sFlags .= " -e 'ssh -p $sPort' --timeout='$sTimeout'";
        $sFlags .= " --bwlimit='$sBandwidth'" if $sBandwidth;
        if ($sRsyncPass) {
            ($fhwPass, $sPassFile)= $self->tempfile();
            print $fhwPass $sRsyncPass;
            close $fhwPass;
            $sFlags .= " --password-file=\"$sPassFile\""
        }
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

    my ($sRsyncOut, $sRsyncErr, $iRsyncExit, $sError)= $self->run_cmd($sRsyncCmd);
    $self->log($self->errorMsg($sError)) if $sError;
    $self->log($self->warnMsg("rsync exited with result ".  $iRsyncExit)) if $iRsyncExit;
    my @sRsyncError= split(/\n/, $sRsyncErr || '');
    $self->log($self->errorMsg(@sRsyncError)) if @sRsyncError;
    my @sRsyncStat= ();

    for (split(/\n/, $sRsyncOut || '')) {
        push @sRsyncStat, $_ unless /^([^\/]+\/)+$/;
    }

    my @sRsyncFiles= ();
    push @sRsyncFiles, shift @sRsyncStat while ((scalar @sRsyncStat) && $sRsyncStat[0] !~ /^Number of .*\:\s+\d+$/);

    $self->log([ 3, @sRsyncFiles ]);
    $self->log('*** Rsync Statistics: ***', @sRsyncStat);

    return 0;
}

sub build_dirhash {
    my $self= shift;
    my $sFile= shift;
    my $sFilter= shift;
    my $hDirHash= shift || { };

    if ($sFile =~ s/^([^\/]*)\///) {
        my $sDirPart= $1;
        $hDirHash->{$sDirPart}= {} unless $hDirHash->{$sDirPart};
        $hDirHash->{$sDirPart}{SUBDIR}= $self->build_dirhash($sFile, $sFilter, $hDirHash->{$sDirPart}{SUBDIR});
    }
    else {
        $hDirHash->{$sFile}= {} unless $hDirHash->{$sFile};
        $hDirHash->{$sFile}{FILTER}= $sFilter;
    }
    return $hDirHash
}

sub unfold_dirhash {
    my $self= shift;
    my $hDirHash= shift;
    my $hMode= shift || { FILES => 1, DIRS => 1, };
    my $sBaseDir= shift || '';
    my $sResult= '';

    # sort config
    my $bPlaceStarBeforeAll= 1; # place single stars before all other pathes

    my $sReplMapSrc= quotemeta "[?*";
    my $sReplMapDst= quotemeta "\xFD\xFE\xFF";
    if ($bPlaceStarBeforeAll) {
        $sReplMapSrc= quotemeta "*[?+";
        $sReplMapDst= quotemeta "\x00\xFD\xFE\xFF";
    }

    # automatically sort '[?*' to end of list: replace those chars with 0xFD-0xFF
    my @Dirs= keys(%$hDirHash);
    map {
        s/([\+\#\;\x00\xF0-\xFF])/"#".ord($1).";"/ge; # replace original 0xF0-0xFF and special chars with "#ASCII;" to preserve original chars
        s/\*\*/\+/ if $bPlaceStarBeforeAll; # replace "**" with "+"
#        tr/\*\[\?\+/\x00\xFD-\xFF/;  # replace wildcard chars
        eval "tr/$sReplMapSrc/$sReplMapDst/";  # replace wildcard chars
    } @Dirs;
    @Dirs= sort @Dirs; # sort to place wildcards at the end
    map {
#        tr/\x00\xFD-\xFF/\*\[\?\+/; # rereplace wildcard chars
        eval "tr/$sReplMapDst/$sReplMapSrc/"; # rereplace wildcard chars
        s/\+/\*\*/ if $bPlaceStarBeforeAll; # rereplace "+" with "**"
        s/\#(\d+)\;/chr($1)/ge; # rereplace replaced original chars
    } @Dirs;

    # for directories: put empty dirs (current dir) at the end to allow subdirectories filter
    # for files: files with exact directories should be placed before those without -> leave on top
    if ($hMode->{DIRS} && @Dirs && $Dirs[0] eq '') {
        push @Dirs, (shift @Dirs);
    }

    foreach my $sDir (@Dirs) {
        $sResult.= $self->unfold_dirhash($hDirHash->{$sDir}{SUBDIR}, $hMode, "$sBaseDir$sDir/") if $hDirHash->{$sDir}{SUBDIR};
        if ($hDirHash->{$sDir}{FILTER}) {
            # files are those with non-empty $sDir and not ending with "**"
            # directories have empty $sDir or end with "**"
            my $bIsFile= $sDir && $sDir !~ /\*\*$/;

            $sResult.= "$hDirHash->{$sDir}{FILTER} $sBaseDir$sDir\n" if $hMode->{FILES} && $bIsFile || $hMode->{DIRS} && !$bIsFile;
        }
    }
    return $sResult;
}

1;

