#!/usr/bin/perl

package Rabak::Peer;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;
no warnings 'redefine';

use vars qw(@ISA);

use Rabak::Conf;
use Rabak::Log;

@ISA = qw(Rabak::Conf);

use Data::Dumper;
use File::Temp ();
use IPC::Run qw(start pump finish);

=head1 DESCRIPTION

Peer.pm is an abstract class for local or remote objects (file, databases etc.).
It provides some basic filesystem operations on peer's system and 
methods for command execution.

=over 4

=cut

sub new {
    my $class= shift;
    my $sName= shift;
    my $hParentConf= shift;
    
    my $self= $class->SUPER::new($sName, $hParentConf);
    $self->{ERRORCODE}= 0;
    $self->{DEBUG}= 0;
    $self->{ERRORMSG}= '';
    $self->{LAST_RESULT}= {
        stdout => '',
        stderr => '',
        exit => 0,
        error => '',
    };
    $self->{TEMPFILES}= [];
    $self->{LOCAL_TEMPFILES}= [];
    $self->{TEMP_RT_ENV}= undef;
    $self->{PRETEND}= undef;

    bless $self, $class;

}

# IMPORTANT: define all used properties here, order will be used for show
sub PropertyNames {
    return ('host', 'port', 'user', 'path', 'protocol', 'identity_files', 'timeout', 'bandwidth', shift->SUPER::PropertyNames());
}

sub newFromConf {
    my $class= shift;
    my $oOrigConf= shift;
    
    my $new= $class->SUPER::newFromConf($oOrigConf);

    my $sPath= $new->get_value("path");
    
    if ($sPath) {
        # remove leading "file://" etc.
        warn("Internal error: '$1' should already have been removed. Please file a bug report with config included!") if $sPath=~ s/^(\w+\:\/\/)//;
        # extract hostname, user and port
        if ($sPath=~ s/^(\S+?\@)?([\-0-9a-z\.]+)(\:\d+)?\://i) {
            my $sUser= $1 || '';
            my $sHost= $2;
            my $iPort= $3;
            $sUser=~ s/\@$//;
            $iPort=~ s/^\:// if $iPort;
            $new->set_value("host", $sHost);
            $new->set_value("user", $sUser) if $sUser;
            $new->set_value("port", $iPort) if $iPort;
        }
        $new->set_value("path", $sPath);
    }

    # print Data::Dumper->Dump([$self->{VALUES}]); die;
    return $new;
}

sub cleanupTempfiles {
    my $self= shift;

    for my $sTempFile (@{$self->{TEMPFILES}}) {
        $self->rmtree($sTempFile);
    }
    $self->{TEMPFILES}= [];
    $self->{LOCAL_TEMPFILES}= [];
}

sub local_tempfile {
    my $self= shift;

#    $self= $self->new() unless ref $self;
#    $sDir = $self->get_value("tempdir");

    my $tempfh= File::Temp->new(TEMPLATE => 'rabak-XXXXXX', UNLINK => 1, TMPDIR => 1);
    # remember $tempfh to keep it in scope (will be unlinked otherwise) 
    push @{$self->{LOCAL_TEMPFILES}}, $tempfh;
    return ($tempfh, $tempfh->filename()) if wantarray;
    return $tempfh->filename();
}

sub local_tempdir {
    my $self= shift;
    
#    $self= $self->new() unless ref $self;
#    my $sDir= $self->get_value("tempdir");

    my $tempdir= File::Temp->newdir('rabak-XXXXXX', CLEANUP => 1, TMPDIR => 1);
    # remember $tempdir to keep it in scope (will be unlinked otherwise) 
    push @{$self->{LOCAL_TEMPFILES}}, $tempdir;
    return $tempdir->dirname();
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

sub is_remote {
    my $self= shift;
    return $self->get_value("host");
}

# may be overridden (Mountable.pm)
sub getPath {
    my $self= shift;
    my $sPath= shift || $self->get_value("path");

    return $sPath;
}

sub getFullPath {
    my $self= shift;
    my $sPath= $self->getPath(shift);

    return $self->getUserHostPort(":") . "$sPath"
}

sub getUserHost {
    my $self= shift;
    my $sSeparator= shift || '';

    return "" unless $self->is_remote();

    my $sUser= $self->get_value("user");
    return ($sUser ? "$sUser\@" : "") .
        $self->get_value("host") .
        $sSeparator;
}

sub getUserHostPort {
    my $self= shift;
    my $sSeparator= shift || '';

    return "" unless $self->is_remote();

    my $iPort= $self->get_value("port", 22);
    return $self->getUserHost() .
        ($iPort == 22 ? "" : ":$iPort") .
        $sSeparator;
}

sub setPretend {
    my $self= shift;
    my $bPretend= shift;
    $self->{PRETEND}= $bPretend;
}

sub pretend {
    my $self= shift;
    return $self->{PRETEND};
}

# quote for shell execution
sub ShellQuote {
    my $self= shift;
    my @sVals= @_;
    
    # character that don't need to be quoted
    # element will be quoted if it contains other chars
    my $sNoQuoteChars= '\w\-\=\.';

    @sVals= map {
        if (/[^$sNoQuoteChars]/s || $_ eq '') {
            # quote "'"
            s/\'/\'\\\'\'/gs;
            # don't include "--param="-part in quotes if possible (for cosmetic reasons)
            s/^([$sNoQuoteChars]+?\=)?(.*)$/\'$2\'/s;
            $_= $1 . $_ if defined $1;
        }
        $_;
    } @sVals;

    return @sVals if wantarray;
    return join ' ', @sVals;
}

# run command locally or remote
# result: stdout of cmd
sub savecmd {
    my $self= shift;
    my $cmd= shift;
    my $hHandles= shift || {};

    $self= $self->new() unless ref $self;

    $self->run_cmd($cmd, $hHandles);
    $self->_set_error($self->{LAST_RESULT}{stderr});
    $?= $self->{LAST_RESULT}{exit} || 0; # set standard exit variable
    return $self->{LAST_RESULT}{stdout} || '';
}

=item run_cmd($sCmd, $bPiped)

Runs a command either locally or remote.

Result: (stdout, stderr, exit code)

=cut

sub run_cmd {
    my $self= shift;
    my $cmd= shift;
    my $hHandles= shift || {};

    $self= $self->new() unless ref $self;

    print "************* COMMAND START ***************\n" .
        "$cmd\n" .
        "************** COMMAND END ****************\n" if $self->{DEBUG};
    print "************* STDIN START ***************\n" .
        "$hHandles->{STDIN}\n" .
        "************** STDIN END ****************\n" if $self->{DEBUG} && $hHandles->{STDIN};

    return $self->_run_ssh_cmd($cmd, $hHandles) if $self->is_remote();
    return $self->_run_local_cmd($cmd, $hHandles);
}

# creates function for output line buffering (for stdout/err handling)
sub _outbufSplitFact {
    my $self= shift;
    my $f= shift; # function to call with lines array
    
    my $sBuffer = "";
    
    return sub {
        # flush buffer if there was no argument
        unless (@_) {
            return unless length $sBuffer;
            my $sBuffer2= $sBuffer;
            $sBuffer = "";
            return $f->($sBuffer2);
        }
        $sBuffer.= join "", @_;
        # return array of lines up to last '\n'
        return $f->(split(/\n/, $1)) if $sBuffer =~ s/^(.*)\n([^\n]*)$/$2/s;
    };
}

sub _prepare_io_handles {
    my $self= shift;
    my $hHandles= shift;
    
    my ($fStdIn, $fStdOut, $fStdErr);
    # prepare standard i/o handles
    $fStdIn= $hHandles->{STDIN}   || sub {undef};
    $fStdOut= $hHandles->{STDOUT} ||
        sub {$self->{LAST_RESULT}{stdout}.= join "\n", @_, ""};
    $fStdErr= $hHandles->{STDERR} ||
        sub {$self->{LAST_RESULT}{stderr}.= join "\n", @_, ""};
    
    # if stdin is a scalar create a function returning its value once
    unless (ref $fStdIn) {
        my @aStdIn= ($fStdIn);
        $fStdIn= sub {shift @aStdIn};
    }

    # stdout/err functions will be line buffered unless forbidden
    $fStdOut = $self->_outbufSplitFact($fStdOut) unless $hHandles->{STDOUT_UNBUFFERED}; 
    $fStdErr = $self->_outbufSplitFact($fStdErr) unless $hHandles->{STDERR_UNBUFFERED};

    return ($fStdIn, $fStdOut, $fStdErr);
}

# run command locally
# $aCmd: Command to be run (array reference or scalar)
# $hHandles->{STDIN}: func ref to get stdin or scalar to be fed (optional)
# $hHandles->{STDOUT}: func ref to handle stdout, gets array of lines if line buffered (optional)
# $hHandles->{STDERR}: func ref to handle stderr, gets array of lines if line buffered (optional)
# $hHandles->{STDOUT_UNBUFFERED}: if false, stdout will be handled line buffered
# $hHandles->{STDERR_UNBUFFERED}: if false, stderr will be handled line buffered
sub _run_local_cmd {
    my $self= shift;
    my $aCmd= shift;
    my $hHandles= shift || {};
    
    $self= $self->new() unless ref $self;

    $self->{LAST_RESULT}= {
        stdout => '',
        stderr => '',
        exit => -1,
        error => '',
    };

    my ($fStdIn, $fStdOut, $fStdErr)= $self->_prepare_io_handles($hHandles);

    # start $aCmd in shell context if its a scalar
    # ($sCmd should be an array reference to avoid shell,
    #   but then we had to handle redirects and pipes properly)
    $aCmd= [qw( sh -c ), $aCmd] unless ref $aCmd;

    my $h= start($aCmd, $fStdIn, $fStdOut, $fStdErr);

    $h->pump() while $h->pumpable();

    $h->finish();
    
    # flush stdout/err handles if line buffered
    $fStdOut->() unless $hHandles->{STDOUT_UNBUFFERED};
    $fStdErr->() unless $hHandles->{STDERR_UNBUFFERED};
    
    $self->{LAST_RESULT}{exit}=  $h->result;

    $self->_set_error($self->{LAST_RESULT}{stderr});

    return (
        $self->{LAST_RESULT}{stdout},
        $self->{LAST_RESULT}{stderr},
        $self->{LAST_RESULT}{exit},
        $self->{LAST_RESULT}{error},
    );
}

sub build_ssh_cmd {
    my $self= shift;
    my $sCmd= shift;

    die "Peer.pm: No command specified!" unless defined $sCmd;
    die "Peer.pm: No host specified!" unless defined $self->get_value("host");

    my @sSshCmd= ('ssh');

    my $p= $self->get_value('port');
    push @sSshCmd, '-p', $p if $p;
    $p= $self->get_value("protocol") || '';
    push @sSshCmd, "-$p" if $p eq '1' || $p eq '2';
    push @sSshCmd, map {('-i', $_)} $self->resolveObjects("identity_files");
#    push @sSshCmd, '-vvv' if $self->{DEBUG};

    push @sSshCmd, $self->getUserHost();
    push @sSshCmd, $sCmd;
    return scalar $self->ShellQuote(@sSshCmd);
}

sub _run_ssh_cmd {
    my $self= shift;
    my $sCmd= shift;
    my $hHandles= shift || {};

    my $sRunCmd= '';

    $sRunCmd= $self->build_ssh_cmd($sCmd);
    print "SSH: running [$sRunCmd]\n" if $self->{DEBUG};

    print "WARNING: Trying to access remote host \"" . $self->get_value("host") . "\"!\n" if $self->get_switch("warn_on_remote_access");

    return $self->_run_local_cmd($sRunCmd, $hHandles);
}

# evaluates perl script remote or locally
sub run_perl {
    my $self= shift;
    my $sPerlScript= shift;
    my $refInVars= shift || {}; # input vars have to be references or skalars
    my $sOutVar= shift;
    my $hHandles= shift || {};

    die "Rabak::Peer->run_perl() may not have an output variable defined and a handle for STDOUT"
        . " at the same time!" if $sOutVar && exists $hHandles->{STDERR};

    # run script as command if it's remote or STDIN/STDOUT handles are defined
    # (will be "eval"ed otherwise)
    my $bRunAsCommand= $hHandles || $self->is_remote();

    # define and set "incoming" variables
    my $sPerlVars= '';
    for my $sKey (keys %$refInVars) {
        $sPerlVars.= 'my ' . Data::Dumper->Dump([$refInVars->{$sKey}], [$sKey]);
    }
    # define result variable
    $sPerlVars.= "my $sOutVar;\n" if $sOutVar;

    # dump result variable to set $OUT_VAR at the end of script execution
    my $sPerlDump= '';
    if ($sOutVar) {
        $sPerlDump= 'print ' if $bRunAsCommand;
        $sPerlDump.= "Data::Dumper->Dump([\\$sOutVar], ['OUT_VAR']);";;
    }

    # build modified perl script
    $sPerlScript= "
        use Data::Dumper;
        $sPerlVars
        $sPerlScript
        $sPerlDump
        __END__
    ";

    if ($self->{DEBUG}) {
        # extract script name (is comment in first line)
        my $sScriptName= '';
        $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\s*\#\s*(\w+)\s?\(\s*\)\s*$//m;

        print "************* SCRIPT$sScriptName START ***************\n" .
            "$sPerlScript\n" .
            "************** SCRIPT$sScriptName END ****************\n";
    }

    # now execute script
    my $result;
    if ($bRunAsCommand) {
        if (exists $hHandles->{STDIN}) {
            $self->run_cmd(scalar $self->ShellQuote('perl', '-e', $sPerlScript), $hHandles);
        }
        else {
            $hHandles->{STDIN}= $sPerlScript;
            $self->run_cmd('perl', $hHandles);
        }
        $self->_set_error($self->{LAST_RESULT}{stderr});
        print 'ERR: ' . $self->{LAST_RESULT}{stderr} . "\n" if $self->{DEBUG} && $self->{LAST_RESULT}{stderr};
        $result= $self->{LAST_RESULT}{exit} ? undef : $self->{LAST_RESULT}{stdout};
    }
    else {
        $result= eval $sPerlScript;
        if ($@) {
            $self->_set_error($@);
            $result= undef;
        }
    }

    print "OUT: $result\n" if $self->{DEBUG} && $result;

    # extract script's result (if everything was ok, eval($result) sets $OUT_VAR)
    my $OUT_VAR = undef;
    eval $result if $result && $sOutVar;
    return $OUT_VAR;
}

####################################################################################################
# PEER COMMANDS
####################################################################################################

# returns directory listing
# if bFileType is set, appends file type character on every entry
sub getDir {
    my $self= shift;
    my $sPath= $self->getPath(shift);
    my $bFileType= shift;

    my $sPerlScript= '
        # getDir()
        use Cwd;
        $sPath= Cwd::abs_path($sPath);
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

    return @{$self->run_perl($sPerlScript, {
            'sPath' => $sPath,
            'bFileType' => $bFileType,
        }, '@Dir'
    ) || []};
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
        use Cwd;
        
        %Dir= ();
        my @queue= ({
            path => Cwd::abs_path($sPath),
            level => $iLevel,
            result => \%Dir,
        });

        while (my $hPath = shift @queue) {
            my $sPath = $hPath->{path};
            my $iLevel = $hPath->{level};
            my $hResult = $hPath->{result};

            my $hDir;

            next unless opendir $hDir, $sPath;

            my @sFiles = map {"$sPath/$_"} grep {!/^\.\.?$/} readdir $hDir;
            closedir $hDir;

            map {
                $hResult->{$_}= (-l) ? readlink : (-d) ? {} : "";
            } @sFiles;

            unshift @queue, map {
                {
                    path => $_,
                    level => $iLevel - 1,
                    result => $hResult->{$_},
                }
            } grep {ref $hResult->{$_}} @sFiles if $iLevel > 0;
        }
    ';

    return %{
        $self->run_perl(
            $sPerlScript,
            {
                "sPath" => $sPath,
                "iLevel" => $iLevel,
            },
            '%Dir',
        ) || {}
    };
}

# makes sure the given file exists locally
sub getLocalFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $sFile unless $self->is_remote();
    
    my ($fh, $sTmpName) = $self->local_tempfile();
    my $hHandles= {
        STDOUT => sub {
            print $fh @_;
        },
        STDOUT_UNBUFFERED => 1,
    };
    $self->savecmd(scalar $self->ShellQuote('cat', $sFile), $hHandles);
    CORE::close $fh;
    return $sTmpName;
}

# copies a local (temp) file to the remote host
sub copyLocalFileToRemote {
    my $self= shift;
    my $sLocFile= shift;
    my $sRemFile= $self->getPath(shift);
    my $bAppend= shift || 0;

    $self->_set_error();

    unless ($self->is_remote()) {
        $sLocFile= $self->getPath($sLocFile);
        return 1 if $sLocFile eq $sRemFile;
        $sLocFile= $self->ShellQuote($sLocFile);
        $sRemFile= $self->ShellQuote($sRemFile);
        if ($bAppend) {
            $self->_set_error(`cat $sLocFile 2>&1 >> $sRemFile`);
        }
        else {
            $self->_set_error(`cp -f $sLocFile $sRemFile 2>&1`);
        }
        return $self->get_error ? 0 : 1;
    }

    my $fh;
    if (CORE::open $fh, $sLocFile) {
        my $sPipe= $bAppend ? '>>' : '>';
        my $iBufferSize= 10240;

        my $hHandles= {
            STDIN => sub {
                my $sData;
                return $sData if read $fh, $sData, $iBufferSize;
                return undef;
            }
        };

        my ($stdout, $stderr, $exit) = $self->_run_ssh_cmd("cat - $sPipe " . $self->ShellQuote($sRemFile), $hHandles);

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
    
    return 1 if $self->pretend();

    return ${$self->run_perl('
            # mkdir()
            $result= -d $sPath || CORE::mkdir $sPath;
        ', { "sPath" => $sPath }, '$result'
    ) || \undef};
}

sub symlink {
    my $self= shift;
#    my $sOrigFile= $self->getPath(shift);
    my $sOrigFile= shift;
    my $sSymLink= $self->getPath(shift);

    return ${$self->run_perl('
            # symlink()
            $result= CORE::symlink $sOrigFile, $sSymLink;
        ', {
            "sOrigFile" => $sOrigFile,
            "sSymLink" => $sSymLink,
        }, '$result'
    ) || \undef};
}

sub unlink {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->run_perl('
            # unlink()
            $result= CORE::unlink $sFile;
        ', { "sFile" => $sFile, }, '$result'
    ) || \undef};
}

sub df {
    my $self= shift;
    my $sDir= $self->getPath(shift);
    my @sParams= @_;

    return $self->savecmd($self->ShellQuote('df', @sParams, $sDir));
}

sub isDir {
    my $self= shift;
    my $sDir= $self->getPath(shift);

    return ${$self->run_perl('
            # isDir()
            $result= -d $sDir;
        ', { 'sDir' => $sDir, }, '$result'
    ) || \undef};
}

sub isReadable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->run_perl('
            # isReadable()
            $result= -r $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub isWritable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->run_perl('
            # isWritable()
            $result= -w $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub isFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->run_perl('
            # isFile()
            $result= -f $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub isSymlink {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->run_perl('
            # isSymlink()
            $result= -l $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

# abs_path *MUST NOT* use getPath!! would result in an infinte loop
sub abs_path {
    my $self= shift;
    my $sFile= shift || '.'; # !! path *NOT* relative to target path but to cwd
    
    return ${$self->run_perl('
            # abs_path()
            use Cwd;
            $result= Cwd::abs_path($sFile);
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub glob {
    my $self= shift;
    my $sFile= shift;

    return @{$self->run_perl('
            # glob()
            @result= glob($sFile);
        ', { 'sFile' => $sFile, }, '@result'
    ) || []};
}

sub rename {
    my $self= shift;
    my $sOldFile= shift;
    my $sNewFile= shift;

    return ${$self->run_perl('
            # rename()
            $result= CORE::rename($sOldFile, $sNewFile);
        ', { 'sOldFile' => $sOldFile, 'sNewFile' => $sNewFile, }, '$result'
    ) || \undef};
}

sub echo {
    my $self= shift;
    my $sFile= $self->getPath(shift);
    my @sLines= @_;

    my $hHandles= {
        STDIN => sub {
            my $sLine= shift @sLines;
            return undef unless defined $sLine;
            chomp $sLine;
            return $sLine . "\n";
        },
    };

    $self->savecmd('cat - >> ' . $self->ShellQuote($sFile), $hHandles);
}

sub cat {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $self->savecmd(scalar $self->ShellQuote('cat', $sFile));
}

sub mount {
    my $self= shift;
    my @sParams= @_;

    return $self->savecmd(scalar $self->ShellQuote('mount', @sParams));
}

sub umount {
    my $self= shift;
    my @sParams= @_;

    return $self->savecmd(scalar $self->ShellQuote('umount', @sParams));
}

sub tempfile {
    my $self= shift;

    $self= $self->new() unless ref $self;
    my $sDir= File::Spec->tmpdir;
#    $sDir = $self->get_value("tempdir");
    my $sFileName= ${$self->run_perl('
            # tempfile
            use File::Temp;
            my @result= File::Temp->tempfile("rabak-XXXXXX", UNLINK => 1, DIR => $sDir);
            CORE::close $result[0];
            $sFileName= $result[1];
        ', { 'sDir' => $sDir, }, '$sFileName',
    ) || \undef};
    push @{$self->{TEMPFILES}}, $sFileName if $sFileName;
    return $sFileName;
}

sub tempdir {
    my $self= shift;

    $self= $self->new() unless ref $self;
    my $sDir= File::Spec->tmpdir;
#    $sDir= $self->get_value("tempdir");
    my $sDirName= ${$self->run_perl('
            # tempdir
            use File::Temp;
            $sDirName= File::Temp->tempdir("rabak-XXXXXX", CLEANUP => 0, DIR => $sDir);
        ', { 'sDir' => $sDir, }, '$sDirName',
    ) || \undef};
    push @{$self->{TEMPFILES}}, $sDirName if $sDirName;
    return $sDirName
}

sub rmtree {
    my $self= shift;
    my $sTree= $self->getPath(shift);

    die "Rabak::Peer::rmtree called with dangerous parameter ($sTree)!" if $sTree eq '' || $sTree eq '/' || $sTree=~ /\*/;

    $self= $self->new() unless ref $self;
    $sTree= $self->ShellQuote($sTree);
    return $self->savecmd("if [ -e $sTree ]; then rm -rf $sTree; fi");
}

=back

=cut

1;
