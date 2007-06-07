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
        DEBUG => 1,
        SSH_DEBUG => 0,
    };
    for my $sParam qw(PATH HOST USER PASSWD PORT PROTOCOL) {
        $self->{$sParam}= $hParams{$sParam} if $hParams{$sParam};
    }

    bless $self, $class;
}

sub remote {
    my $self= shift;
    return $self->{HOST};
}

sub close {
    my $self= shift;
    undef $self->{SSH};
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->_getPath(shift);

    return "$self->{USER}\@$self->{HOST}\:$sPath" if $self->remote;
    return $sPath;
}

sub _getPath {
    my $self= shift;
    my $sPath= shift || '';
    $sPath= "$self->{PATH}/$sPath" unless $sPath=~ /^\//;
    $sPath=~ s/\/+/\//;
    $sPath=~ s/\/$//;
    return $sPath;
}

sub _ssh {
    my $self= shift;

    unless ($self->{SSH}) {
        $self->{SSH}= Net::SSH::Perl->new($self->{HOST},
            debug => $self->{SSH_DEBUG},
            port => $self->{PORT},
            protocol => $self->{PROTOCOL},
        );
        $self->{SSH}->login($self->{USER}, $self->{PASSWD});
    }
    return $self->{SSH};
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

    my $sPerlVars= "";
    for my $sKey (keys %$refInVars) {
        $sPerlVars.= "my " . Data::Dumper->Dump([$$refInVars{$sKey}], [$sKey]);
    }
    $sPerlVars.= "my $sOutVar;\n" if $sOutVar;

    my $sPerlDump= "";
    if ($sOutVar) {
        if ($self->remote) {
            $sPerlDump= "print Data::Dumper->Dump([\\$sOutVar], [\"OUT_VAR\"]);";
        }
        else {
            $sPerlDump= "Data::Dumper->Dump([\\$sOutVar], [\"OUT_VAR\"]);";
        }
    }
    $sPerlScript= "
        use Data::Dumper;
        $sPerlVars
        $sPerlScript
        $sPerlDump
        ";

    my $result;
    if ($self->remote) {
        $result= $self->_sshperl($sPerlScript);
    }
    else {
        $result= eval $sPerlScript;
    }
    my $OUT_VAR = undef;
    eval($result) if $result;
    return $OUT_VAR;
}

sub _sshperl {
    my $self= shift;
    my $sPerlScript= shift;

    # replace "'" chars for shell execution
    $sPerlScript=~ s/\'/\'\\\'\'/g;
    # compress script
    $sPerlScript=~ s/^\s+//mg;
    my $sScriptName= '';
    $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\#\s*(\w+)\s?\(\s*\)\s*$//m;

    my ($stdout, $stderr, $exit)= $self->_sshcmd("perl -e '$sPerlScript'");
    if ($self->{DEBUG}) {
        print "************* SCRIPT$sScriptName START ***************\n" .
            "$sPerlScript\n" .
            "************** SCRIPT$sScriptName END ****************\n";
        print "OUT: $stdout\n" if $stdout;
        print "ERR: $stderr\n" if $stderr;
    }
    return $exit ? '' : $stdout;
}

# returns directory listing
# if bFileType is set, appends file type character on every entry
sub getDir {
    my $self= shift;
    my $sPath= $self->_getPath(shift);
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
    my $sPath= $self->_getPath(shift);
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
    my $sPath= $self->_getPath(shift);

    return ${$self->_saveperl('
        # mkdir()
        $result= -d $sPath || mkdir $sPath;
    ', { "sPath" => $sPath }, '$result')};
}

sub symlink {
    my $self= shift;
    my $sOrigFile= $self->_getPath(shift);
    my $sSymLink= $self->_getPath(shift);

    return ${$self->_saveperl('
            # symlink()
            $result= symlink $sOrigFile, $sSymLink;
        ', {
            "sOrigFile" => $sOrigFile,
            "sSymLink" => $sSymLink,
        }, '$result'
    )};
}

sub unlink {
    my $self= shift;
    my $sFile= $self->_getPath(shift);

    return ${$self->_saveperl('
            # unlink()
            $result= unlink $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

sub df {
    my $self= shift;
    my $sDir= $self->_getPath(shift);
    my $sParams= shift || '';
    if ($self->remote) {
        my ($stdout, $stderr, $exit) = $self->_sshcmd("df $sParams '$sDir'");
        return $stdout;
    }
    else {
        return `df -k "$sDir"`;
    }
}

sub isDir {
    my $self= shift;
    my $sDir= $self->_getPath(shift);

    return ${$self->_saveperl('
            # isDir()
            $result= -d $sDir;
        ', { "sDir" => $sDir, }, '$result'
    )};
}

sub isWritable {
    my $self= shift;
    my $sFile= $self->_getPath(shift);

    return ${$self->_saveperl('
            # isWritable()
            $result= -w $sFile;
        ', { "sFile" => $sFile, }, '$result'
    )};
}

1;
