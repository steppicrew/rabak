#!/usr/bin/perl

package RabakLib::Path;

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
            PORT => 22,
        },
    };
    for my $key (keys %hParams) {
        $self->{VALUES}->{uc $key}= $hParams{$key};
    }

    bless $self, $class;
}

sub get_value {
    my $self= shift;
    my $sValName= shift;
    return $self->{VALUES}->{uc $sValName};
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

    return "$self->{VALUES}->{USER}\@$self->{VALUES}->{HOST}\:$sPath" if $self->remote;
    return $sPath;
}

sub getPath {
    my $self= shift;
    my $sPath= shift || '';
    $sPath= "$self->{VALUES}->{PATH}/$sPath" unless $sPath=~ /^\//;
    $sPath=~ s/\/+/\//;
    $sPath=~ s/\/$//;
    return $sPath;
}

sub _ssh {
    my $self= shift;

    unless ($self->{SSH}) {
        $self->{SSH}= Net::SSH::Perl->new($self->{VALUES}->{HOST},
            debug => $self->{SSH_DEBUG},
            port => $self->{VALUES}->{PORT},
            protocol => $self->{VALUES}->{PROTOCOL},
        );
        $self->{SSH}->login($self->{VALUES}->{USER}, $self->{VALUES}->{PASSWD});
    }
    return $self->{SSH};
}

sub _savecmd {
    my $self= shift;
    my $cmd= shift;

    print "************* COMMAND $cmd START ***************\n" .
        "$cmd\n" .
        "************** COMMAND $cmd END ****************\n" if $self->{DEBUG};

    if ($self->remote) {
        my ($stdout, $stderr, $exit) = $self->_sshcmd("$cmd");
        return $stdout || '';
    }
    else {
        return `$cmd`;
    }
}

sub _sshcmd {
    my $self= shift;
    my $cmd= shift;
    my $ssh= shift || $self->_ssh;

    return $ssh->cmd($cmd);
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

    # compress script
    $sPerlScript=~ s/^\s+//mg;
    # extract script name
    my $sScriptName= "";
    $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\#\s*(\w+)\s?\(\s*\)\s*$//m;

    print "************* SCRIPT$sScriptName START ***************\n" .
        "$sPerlScript\n" .
        "************** SCRIPT$sScriptName END ****************\n" if $self->{DEBUG};

    # now execute script
    my $result;
    if ($self->remote) {
        $result= $self->_sshperl($sPerlScript);
    }
    else {
        $result= eval $sPerlScript;
    }

    print "OUT: $result\n" if $self->{DEBUG} && $result;

    # extract scripts result (if everything was ok, eval($result) sets $OUT_VAR)
    my $OUT_VAR = undef;
    eval($result) if $result;
    return $OUT_VAR;
}

sub _sshperl {
    my $self= shift;
    my $sPerlScript= shift;

    # replace "'" chars for shell execution
    $sPerlScript=~ s/\'/\'\\\'\'/g;
    my ($stdout, $stderr, $exit)= $self->_sshcmd("perl -e '$sPerlScript'");
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
        use File::Spec;
        $sPath= File::Spec->rel2abs("$sPath");
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
        use File::Spec;
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
        $sPath= File::Spec->rel2abs("$sPath");
        %Dir= %{_dirlist($sPath, $iLevel)};
    ';

    return %{$self->_saveperl($sPerlScript, {
            "sPath" => $sPath,
            "iLevel" => $iLevel,
        }, '%Dir'
    )};
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

    return $self->_savecmd("df $sParams '$sDir'");
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

sub isWritable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->_saveperl('
            # isWritable()
            $result= -w $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub copyLoc2Rem {
    my $self= shift;
    my $sLocFile= shift;
    my $sRemFile= $self->getPath(shift);

    my $fh;
    if (CORE::open $fh, "$sLocFile") {
        while (<$fh>) {
            chomp;
            s/\'/\'\\\'\'/;
            $self->_sshcmd("echo '$_' >> '$sRemFile'");
        }
        CORE::close $fh;
        return 1;
    }
    return 0;
#    return $self->_sshcmd("scp -P $sPort '$sLocFile' '$sRemFile'");
}

1;
