#!/usr/bin/perl

package RabakLib::Path;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use Data::Dumper;
use File::Spec ();
use File::Temp ();
use RabakLib::Path::Ssh;

sub new {
    my $class= shift;
    my %hParams= @_;
    my $self= {
        ERRORCODE => 0,
        DEBUG => 0,
#        SSH_DEBUG => 1,
        VALUES => {
            PORT => 22,                     # standard ssh port to connect to
            TEMPDIR => File::Spec->tmpdir,  # directory for temporarily stored data
        },
        ERRORMSG => '',
        LAST_RESULT => {
            stdout => '',
            stderr => '',
            exit => 0,
            error => '',
        },
        TEMPFILES => [],
    };

    map { $self->{VALUES}{uc $_} = $hParams{$_}; } keys(%hParams);

    if ($self->{VALUES}{PATH} && $self->{VALUES}{PATH} =~ s/^(\S+\@)?([\-0-9a-z\.]+)\://i) {
        my $sUser= $1 || '';
        my $sHost= $2;
        $sUser=~ s/\@$//;
        # TODO: implement logging for RabakLib::Path
        print "WARNING: Specifying host and user in path is deprecated!\nPlease use path objects!";
        die "Host specified by object *and* path!" if $self->{VALUES}{HOST};
        die "User specified by object *and* path!" if $self->{VALUES}{USER} && $sUser;
        $self->{VALUES}{HOST}= $sHost;
        $self->{VALUES}{USER}= $sUser if $sUser;
    }

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    bless $self, $class;
}

# delete all non deleted temp files on exit (important for remote sessions)
sub DESTROY {
    my $self= shift;

    for my $sTempFile (@{$self->{TEMPFILES}}) {
        $self->savecmd("if [ -e '$sTempFile' ]; then rm -rf '$sTempFile'; fi");
    }
}

sub local_tempfile {
    my $self= shift;

    $self= $self->new(@_) unless ref $self;
    my $sDir= File::Spec->tmpdir;
    $sDir = $self->get_value("tempdir");
    return @_= File::Temp->tempfile("rabak-XXXXXX", UNLINK => 1, DIR => $sDir);
}

sub local_tempdir {
    my $self= shift;

return $self->tempdir();
    $self= $self->new(@_) unless ref $self;
    my $sDir= File::Spec->tmpdir;
    $sDir= $self->get_value("tempdir");
    return File::Temp->tempdir("rabak-XXXXXX", CLEANUP => 1, DIR => $sDir);
}

sub get_value {
    my $self= shift;
    my $sValName= shift;
    return $self->{VALUES}{uc $sValName};
}

sub _set_value {
    my $self= shift;
    my $sValName= shift;
    my $sValue= shift;

    $self->{VALUES}{uc $sValName} = $sValue;
}

sub get_error {
    my $self= shift;

    return $self->{ERRORMSG};
}

sub get_last_out {
    my $self= shift;
    return $self->{LAST_RESULT}{stdout};
}

sub get_last_error {
    my $self= shift;
    return $self->{LAST_RESULT}{stderr};
}

sub get_last_exit {
    my $self= shift;
    return $self->{LAST_RESULT}{exit};
}

sub _set_error {
    my $self= shift;
    my $sError= shift || '';

    $self->{ERRORMSG}= $sError;
}

sub remote {
    my $self= shift;
    return $self->get_value("host");
}

sub close {
    my $self= shift;
    undef $self->{SSH};
}

sub getFullPath {
    my $self= shift;
    # TODO: find a better way to get full path
    my $sPath= $self->get_value("path") ? $self->getPath(shift) : $self->get_value("db");

    if ($self->remote) {
        $sPath = $self->get_value("host") . "\:$sPath";
        $sPath = $self->get_value("user") . "\@$sPath" if $self->get_value("user");
    }
    return $sPath;
}

sub getPath {
    my $self= shift;
    my $sPath= shift || '.';

    return $sPath unless $self->get_value("path");

    $self->_set_value("path", $self->abs_path($self->get_value("path"))) unless File::Spec->file_name_is_absolute($self->get_value("path"));

    $sPath= File::Spec->canonpath($sPath); # simplify path
    $sPath= File::Spec->rel2abs($sPath, $self->get_value("path")) unless File::Spec->file_name_is_absolute($sPath);
    return $sPath;
}

sub _ssh {
    my $self= shift;

    $self->{SSH}= RabakLib::Path::Ssh->new(%{$self->{VALUES}}) unless $self->{SSH};

    return $self->{SSH};
}

# result: stdout
sub savecmd {
    my $self= shift;
    my $cmd= shift;

    $self= $self->new() unless ref $self;

    $self->run_cmd($cmd);
    $self->_set_error($self->{LAST_RESULT}{stderr});
    $?= $self->{LAST_RESULT}{exit} || 0; # set standard exit variable
    return $self->{LAST_RESULT}{stdout} || '';
}

# result: (stdout, stderr, exit code)
sub run_cmd {
    my $self= shift;
    my $cmd= shift;
    my $bPiped= shift || 0;

    $self= $self->new() unless ref $self;

    print "************* COMMAND START ***************\n" .
        "$cmd\n" .
        "************** COMMAND END ****************\n" if $self->{DEBUG};

    return $self->remote ? $self->_run_ssh_cmd($cmd, undef, $bPiped) : $self->_run_local_cmd($cmd, $bPiped);
}

sub _run_local_cmd {
    my $self= shift;
    my $cmd= shift;
    my $bPiped= shift || 0;

    $self= $self->new(@_) unless ref $self;

    unless ($self->{IO}) {
        my $sTempDir= $self->local_tempdir;
        $self->{IO}= {
            dir => $sTempDir,
            stdout => "$sTempDir/stdout",
            stderr => "$sTempDir/stderr",
        };
    }

    system("( $cmd ) > '$self->{IO}{stdout}' 2> '$self->{IO}{stderr}'");

    my $iExit= $?;
    $self->{LAST_RESULT}= {
        stdout => '',
        stderr => '',
        exit => $iExit,
        error => '',
    };

    if ($iExit == -1) {
        $self->{LAST_RESULT}{error}= "failed to execute: $!";
    }
    elsif ($iExit & 127) {
        $self->{LAST_RESULT}{error}= sprintf "cmd died with signal %d, %s coredump",
            ($iExit & 127), ($iExit & 128) ? "with" : "without";
    }

    if ($bPiped) {
        $self->{LAST_RESULT}{stdout}= $self->{IO}{stdout};
        $self->{LAST_RESULT}{stderr}= $self->{IO}{stderr};
    }
    else {
        my $fh;
        if (-s $self->{IO}{stderr} && open ($fh, $self->{IO}{stderr})) {
            $self->{LAST_RESULT}{stderr}= join '', (<$fh>);
            CORE::close $fh;
        }
        if (-s $self->{IO}{stdout} && open ($fh, $self->{IO}{stdout})) {
            $self->{LAST_RESULT}{stdout}= join '', (<$fh>);
            CORE::close $fh;
        }
        $self->_set_error($self->{LAST_RESULT}{stderr});
    }
    return (
        $self->{LAST_RESULT}{stdout},
        $self->{LAST_RESULT}{stderr},
        $self->{LAST_RESULT}{exit},
        $self->{LAST_RESULT}{error}
    );
}

sub _run_ssh_cmd {
    my $self= shift;
    my $cmd= shift;
    my $stdin= shift;
    my $bPiped= shift || 0;

    my $ssh= $self->_ssh;
    $ssh->cmd($cmd, $stdin, $bPiped);
    $self->{LAST_RESULT}= {
        stdout => $ssh->get_last_out,
        stderr => $ssh->get_last_error,
        exit => $ssh->get_last_exit,
        error => $ssh->get_error,
    };

    return (
        $self->{LAST_RESULT}{stdout},
        $self->{LAST_RESULT}{stderr},
        $self->{LAST_RESULT}{exit},
        $self->{LAST_RESULT}{error}
    );
}

# evaluates perl script remote or locally
sub _saveperl {
    my $self= shift;
    my $sPerlScript= shift;
    my $refInVars= shift || {}; # input vars have to be references or skalars
    my $sOutVar= shift;

    # define and set "incoming" variables
    my $sPerlVars= "";
    for my $sKey (keys %$refInVars) {
        $sPerlVars.= "my " . Data::Dumper->Dump([$$refInVars{$sKey}], [$sKey]);
    }
    # define result variable
    $sPerlVars.= "my $sOutVar;\n" if $sOutVar;

    # dump result variable to set $OUT_VAR at the end of script execution
    my $sPerlDump= "";
    if ($sOutVar) {
        $sPerlDump= "print " if $self->remote;
        $sPerlDump.= "Data::Dumper->Dump([\\$sOutVar], [\"OUT_VAR\"]);";
    }
    # build modified perl script
    $sPerlScript= "
        use Data::Dumper;
        $sPerlVars
        $sPerlScript
        $sPerlDump
    ";

    if ($self->{DEBUG}) {
        # extract script name
        my $sScriptName= "";
        $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\s*\#\s*(\w+)\s?\(\s*\)\s*$//m;

        print "************* SCRIPT$sScriptName START ***************\n" .
            "$sPerlScript\n" .
            "************** SCRIPT$sScriptName END ****************\n";
    }

    # now execute script
    my $result;
    if ($self->remote) {
        $result= $self->_sshperl($sPerlScript);
    }
    else {
        $result= eval $sPerlScript;
        $self->_set_error(join("\n", $@));
    }

    print "OUT: $result\n" if $self->{DEBUG} && $result;

    # extract scripts result (if everything was ok, eval($result) sets $OUT_VAR)
    my $OUT_VAR = undef;
    eval($result) if $result && $sOutVar;
    return $OUT_VAR;
}

sub _sshperl {
    my $self= shift;
    my $sPerlScript= shift;

    # replace "'" chars for shell execution
#    $sPerlScript=~ s/\'/\'\\\'\'/g;
    $self->_run_ssh_cmd("perl", "$sPerlScript");
    $self->_set_error($self->{LAST_RESULT}{stderr});
    print "ERR: " . $self->{LAST_RESULT}{stderr} . "\n" if $self->{DEBUG} && $self->{LAST_RESULT}{stderr};
    return $self->{LAST_RESULT}{exit} ? '' : $self->{LAST_RESULT}{stdout};
}

# returns directory listing
# if bFileType is set, appends file type character on every entry
sub getDir {
    my $self= shift;
    my $sPath= $self->getPath(shift);
    my $bFileType= shift;

    my $sPerlScript= '
        # getDir()
        use Cwd "abs_path";
        $sPath= abs_path $sPath;
        @Dir= (<$sPath/*>);
        @Dir= map {
            if (-l) { # symlinks
                $_.= "@";
            }
            elsif (-d) { # directories
                $_.= "/";
            }
            elsif (-x) { # executables
                $_.= "*";
            }
            elsif (-p) { # FIFOs
                $_.= "|";
            }
            elsif (-S) { # sockets
                $_.= "=";
            }
            else { # other files
                $_.= "#";
            }
        } @Dir if $bFileType;
    ';

    return @{$self->_saveperl($sPerlScript, {
            "sPath" => $sPath,
            "bFileType" => $bFileType,
        }, '@Dir'
    )};
}

# returns cascaded hash table of the given directory
# files point to an emtpy string
# symlinks point to a string containing link target
# dirs point to a hash reference containing the directory entries (or empty hash if iLevel is reached)
sub getDirRecursive {
    my $self= shift;
    my $sPath= $self->getPath(shift);
    my $iLevel= shift || 0;

    my $sPerlScript= '
        # getDirRecursive()
        use Cwd "abs_path";
        sub _dirlist {
            my $sPath= shift;
            my $iLevel= shift;

            return {} if $iLevel < 0;
            my %result = ();
            my @dirs= ();
            while (<$sPath/*>) {
                if (-l) {
                    $result{$_}= readlink;
                }
                elsif (-d) {
                    push @dirs, $_;
                }
                else {
                    $result{$_}= "";
                }
            }
            for my $dir (@dirs) {
                $result{$dir}= _dirlist($dir, $iLevel - 1);
            }
            return \%result;
        }
        $sPath= abs_path $sPath;
        %Dir= %{_dirlist($sPath, $iLevel)};
    ';

    return %{$self->_saveperl($sPerlScript, {
            "sPath" => $sPath,
            "iLevel" => $iLevel,
        }, '%Dir'
    )};
}

# makes sure the given file exists locally
# TODO: use ssh->register_handler for large files
sub getLocalFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $sFile unless $self->remote;
    my ($fh, $sTmpName) = $self->local_tempfile;
    print $fh $self->savecmd("cat '$sFile'");
    CORE::close $fh;
    return $sTmpName;
}

# copies a local (temp) file to the remote host
sub copyLoc2Rem {
    my $self= shift;
    my $sLocFile= shift;
    my $sRemFile= $self->getPath(shift);
    my $bAppend= shift || 0;

    my $iBufferSize= 10240;

    $self->_set_error();

    unless ($self->remote) {
        return 1 if $sLocFile eq $sRemFile;
        if ($bAppend) {
            $self->_set_error(`cat "$sLocFile" >> "$sRemFile" 2>&1`);
        }
        else {
            $self->_set_error(`cp -f "$sLocFile" "$sRemFile" 2>&1`);
        }
        return $self->get_error ? 0 : 1;
    }

    my $fh;
    if (CORE::open $fh, $sLocFile) {
        my $sPipe= $bAppend ? ">>" : ">";
        my $sData;
        my ($stdout, $stderr, $exit);
        while (my $iRead= read $fh, $sData, $iBufferSize) {
            ($stdout, $stderr, $exit) = $self->_run_ssh_cmd("cat - $sPipe \"$sRemFile\"", $sData);
            last if $stderr || $exit;
            $sPipe= ">>";
        }
        $self->_set_error($stderr);
        CORE::close $fh;
        return $stderr ? 0 : 1;
    }
    $self->_set_error("Could not open local file \"$sLocFile\"");
    return 0;
}

sub mkdir {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    return ${$self->_saveperl('
        # mkdir()
        $result= -d $sPath || CORE::mkdir $sPath;
    ', { "sPath" => $sPath }, '$result')};
}

sub symlink {
    my $self= shift;
#    my $sOrigFile= $self->getPath(shift);
    my $sOrigFile= shift;
    my $sSymLink= $self->getPath(shift);

    return ${$self->_saveperl('
            # symlink()
            $result= CORE::symlink $sOrigFile, $sSymLink;
        ', {
            "sOrigFile" => $sOrigFile,
            "sSymLink" => $sSymLink,
        }, '$result'
    )};
}

sub unlink {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # unlink()
            $result= CORE::unlink $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub df {
    my $self= shift;
    my $sDir= $self->getPath(shift);
    my $sParams= shift || '';

    return $self->savecmd("df $sParams '$sDir'");
}

sub isDir {
    my $self= shift;
    my $sDir= $self->getPath(shift);

    return ${$self->_saveperl('
            # isDir()
            $result= -d $sDir;
        ', { "sDir" => $sDir, }, '$result'
    )};
}

sub isReadable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # isReadable()
            $result= -r $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub isWritable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # isWritable()
            $result= -w $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub isFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # isFile()
            $result= -f $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub isSymlink {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # isSymlink()
            $result= -l $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

# abs_path *MUST NOT* use getPath!! would result in an infinte loop
sub abs_path {
    my $self= shift;
    my $sFile= shift; # !! path *NOT* relative to target path but to cwd

    return ${$self->_saveperl('
            # abs_path()
            use Cwd;
            $result= Cwd::abs_path($sFile);
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub glob {
    my $self= shift;
    my $sFile= shift;

    return @{$self->_saveperl('
            # glob()
            @result= glob($sFile);
        ', { "sFile" => $sFile, }, '@result'
    )};
}

sub echo {
    my $self= shift;
    my $sFile= $self->getPath(shift);
    my @sLines= @_;

    for (@sLines) {
        chomp;
        s/\'/\'\\\'\'/;
        $self->savecmd("echo '$_' >> '$sFile'");
    }
}

sub mount {
    my $self= shift;
    my $sParams= shift || '';

    return $self->savecmd("mount $sParams");
}

sub umount {
    my $self= shift;
    my $sParams= shift || '';

    return $self->savecmd("umount $sParams");
}

sub tempfile {
    my $self= shift;

    $self= $self->new(@_) unless ref $self;
    my $sDir= File::Spec->tmpdir;
    $sDir = $self->get_value("tempdir");
    my $sFileName= ${$self->_saveperl('
            # tempfile
            use File::Temp;
            my @result= File::Temp->tempfile("rabak-XXXXXX", UNLINK => 1, DIR => $sDir);
            CORE::close $result[0];
            $sFileName= $result[1];
        ', { "sDir" => $sDir, }, '$sFileName',
    )};
    push @{$self->{TEMPFILES}}, $sFileName;
    return $sFileName;
}

sub tempdir {
    my $self= shift;

    $self= $self->new(@_) unless ref $self;
    my $sDir= File::Spec->tmpdir;
    $sDir= $self->get_value("tempdir");
    my $sDirName= ${$self->_saveperl('
            # tempdir
            use File::Temp;
            $sDirName= File::Temp->tempdir("rabak-XXXXXX", CLEANUP => 0, DIR => $sDir);
        ', { "sDir" => $sDir, }, '$sDirName',
    )};
    push @{$self->{TEMPFILES}}, $sDirName;
    return $sDirName
}

1;
