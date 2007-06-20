#!/usr/bin/perl

package RabakLib::Path;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use Data::Dumper;
use File::Spec ();
use File::Temp ();

# include Net::SSH::Perl or create dummy class
eval "
    use Net::SSH::Perl;
    1;
" or eval "
    sub Net::SSH::Perl::new {
        die \"To use ssh you have to install 'Net::SSH::Perl'!\nOn gentoo simply emerge net-ssh-perl\n\";
    }
";

sub new {
    my $class= shift;
    my %hParams= @_;
    my $self= {
        ERRORCODE => 0,
        DEBUG => 0,
        SSH_DEBUG => 0,
        VALUES => {
            PATH => ".",
            PORT => 22,                     # standard ssh port to connect to
            TEMPDIR => File::Spec->tmpdir,  # directory for temporarily stored data
        },
        ERRORMSG => '',
    };

    map { $self->{VALUES}->{uc $_} = $hParams{$_}; } keys(%hParams);

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    bless $self, $class;
}

sub get_value {
    my $self= shift;
    my $sValName= shift;
    return $self->{VALUES}->{uc $sValName};
}

sub _set_value {
    my $self= shift;
    my $sValName= shift;
    my $sValue= shift;

    $self->{VALUES}->{uc $sValName} = $sValue;
}

sub get_error {
    my $self= shift;

    return $self->{ERRORMSG};
}

sub _set_error {
    my $self= shift;
    my $sError= shift || '';

    $self->{ERRORMSG}= $sError;
}

sub remote {
    my $self= shift;
    return $self->{VALUES}->{HOST};
}

sub close {
    my $self= shift;
    undef $self->{SSH};
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    if ($self->remote) {
        $sPath = $self->get_value("host") . "\:$sPath";
        $sPath = $self->get_value("user") . "\@$sPath" if $self->get_value("user");
    }
    return $sPath;
}

sub getPath {
    my $self= shift;
    my $sPath= shift || '.';

    $self->_set_value("path", $self->abs_path($self->get_value("path"))) unless File::Spec->file_name_is_absolute($self->get_value("path"));

    $sPath= File::Spec->canonpath($sPath); # simplify path
    $sPath= File::Spec->rel2abs($sPath, $self->get_value("path")) unless File::Spec->file_name_is_absolute($sPath);
    return $sPath;
}

sub _ssh {
    my $self= shift;

    my @identity_files= $self->get_value("identity_files") ? split(/\s+/, $self->get_value("identity_files")) : undef;
    unless ($self->{SSH}) {
        $self->{SSH}= Net::SSH::Perl->new($self->get_value("host"),
            debug => $self->{SSH_DEBUG},
            port => $self->get_value("port"),
            protocol => $self->get_value("protocol"),
            identity_files => @identity_files ? \@identity_files : undef,
        );
        $self->{SSH}->login($self->get_value("user"), $self->get_value("passwd"));
    }
    return $self->{SSH};
}

sub savecmd {
    my $self= shift;
    my $cmd= shift;

    print "************* COMMAND START ***************\n" .
        "$cmd\n" .
        "************** COMMAND END ****************\n" if $self->{DEBUG};

    if ($self->remote) {
        my ($stdout, $stderr, $exit) = $self->_sshcmd("$cmd");
        $self->_set_error($stderr);
        $?= $exit; # set standard exit variable
        return $stdout || '';
    }
    else {
        $self->_set_error();
        return `$cmd`;
    }
}

sub _sshcmd {
    my $self= shift;
    my $cmd= shift;
    my $stdin= shift;

    my $ssh= $self->_ssh;

    return $ssh->cmd($cmd, $stdin);
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

    # compress script
    $sPerlScript=~ s/^\s+//mg;
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
    $sPerlScript=~ s/\'/\'\\\'\'/g;
    my ($stdout, $stderr, $exit)= $self->_sshcmd("perl -e '$sPerlScript'");
    $self->_set_error($stderr);
    print "ERR: $stderr\n" if $self->{DEBUG} && $stderr;
    return $exit ? '' : $stdout;
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

sub tempfile {
    my $self= shift;

    $self= $self->new(@_) unless ref $self;
    my $sDir= $self->get_value("tempdir") if ref $self;
#    File::Temp->safe_level( File::Temp::HIGH ); # make sure tempfiles are secure
    return @_= File::Temp->tempfile("rabak-XXXXXX", UNLINK => 1, DIR => $sDir);
}

# makes sure the given file exists locally
# TODO: use ssh->register_handler for large files
sub getLocalFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $sFile unless $self->remote;
    my ($fh, $sTmpName) = $self->tempfile;
    print $fh $self->savecmd("cat '$sFile'");
    CORE::close $fh;
    return $sTmpName;
}

# copies a local (temp) file to the remote host
sub copyLoc2Rem {
    my $self= shift;
    my $sLocFile= shift;
    my $sRemFile= $self->getPath(shift);

    my $iBufferSize= 102400;

    $self->_set_error();

    unless ($self->remote) {
        return 1 if $sLocFile eq $sRemFile;
        $self->_set_error(`mv -f "$sLocFile" "$sRemFile" 2>&1`);
        return $self->get_error ? 0 : 1;
    }

    my $fh;
    if (CORE::open $fh, $sLocFile) {
        my $sPipe= ">";
        my $iOffset= 0;
        my $sData;
        my ($stdout, $stderr, $exit);
        while (my $iRead= read $fh, $sData, $iBufferSize, $iOffset) {
            $iOffset+= $iRead;
            ($stdout, $stderr, $exit) = $self->_sshcmd("cat - $sPipe \"$sRemFile\"", $sData);
            last if $stderr || $exit;
            $sPipe= ">>" if $sPipe eq ">";
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

# TODO: TEXT ONLY!!!
#sub copyLoc2Rem {
#    my $self= shift;
#    my $sLocFile= shift;
#    my $sRemFile= $self->getPath(shift);
#
#    my $fh;
#    if (CORE::open $fh, "$sLocFile") {
#        while (<$fh>) {
#            $self->echo($sRemFile, $_);
#        }
#        CORE::close $fh;
#        return 1;
#    }
#    return 0;
#}

1;
