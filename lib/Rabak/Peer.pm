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

    my $sPath= $new->getValue("path");
    
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
            $new->setValue("host", $sHost);
            $new->setValue("user", $sUser) if $sUser;
            $new->setValue("port", $iPort) if $iPort;
        }
        $new->setValue("path", $sPath);
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

sub localTempfile {
    my $self= shift;
    my %hParams= @_;

    my $sDir = $hParams{DIR} || $self->getValue("tempdir") || File::Spec->tmpdir();
    my $sSuffix= $hParams{SUFFIX} || '';

    my $tempfh= File::Temp->new(
        TEMPLATE => 'rabak-XXXXXX', UNLINK => 1, SUFFIX => $sSuffix, DIR => $sDir,
    );
    # remember $tempfh to keep it in scope (will be unlinked otherwise) 
    push @{$self->{LOCAL_TEMPFILES}}, $tempfh;
    return ($tempfh, $tempfh->filename()) if wantarray;
    $tempfh->close();
    return $tempfh->filename();
}

# DETECTED UNUSED: localTempdir
sub localTempdir {
    my $self= shift;
    my %hParams= @_;

    my $sDir = $hParams{DIR} || $self->getValue("tempdir") || File::Spec->tmpdir();

    my $tempdir= File::Temp->newdir('rabak-XXXXXX', CLEANUP => 1, DIR => $sDir,);
    # remember $tempdir to keep it in scope (will be unlinked otherwise) 
    push @{$self->{LOCAL_TEMPFILES}}, $tempdir;
    return $tempdir->dirname();
}

sub getError {
    my $self= shift;

    return $self->{ERRORMSG};
}

sub getLastOut {
    my $self= shift;
    return $self->{LAST_RESULT}{stdout};
}

sub getLastError {
    my $self= shift;
    return $self->{LAST_RESULT}{stderr};
}

sub getLastExit {
    my $self= shift;
    return $self->{LAST_RESULT}{exit};
}

sub _setError {
    my $self= shift;
    my $sError= shift || '';

    $self->{ERRORMSG}= $sError;
}

sub isRemote {
    my $self= shift;
    return $self->getValue("host");
}

# may be overridden (Mountable.pm)
sub getPath {
    my $self= shift;
    my $sPath= shift || $self->getValue("path");

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

    return "" unless $self->isRemote();

    my $sUser= $self->getValue("user");
    return ($sUser ? "$sUser\@" : "") .
        $self->getValue("host") .
        $sSeparator;
}

sub getUserHostPort {
    my $self= shift;
    my $sSeparator= shift || '';

    return "" unless $self->isRemote();

    my $iPort= $self->getValue("port", 22);
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
sub _savecmd {
    my $self= shift;
    my $cmd= shift;
    my $hHandles= shift || {};

    $self= $self->new() unless ref $self;

    $self->runCmd($cmd, $hHandles);
    $self->_setError($self->{LAST_RESULT}{stderr});
    $?= $self->{LAST_RESULT}{exit} || 0; # set standard exit variable
    return $self->{LAST_RESULT}{stdout} || '';
}

=item runCmd($sCmd, $bPiped)

Runs a command either locally or remote.

Result: (stdout, stderr, exit code)

=cut

sub runCmd {
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

    return $self->_runSshCmd($cmd, $hHandles) if $self->isRemote();
    return $self->_runLocalCmd($cmd, $hHandles);
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

sub _prepareIoHandles {
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
sub _runLocalCmd {
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

    my ($fStdIn, $fStdOut, $fStdErr)= $self->_prepareIoHandles($hHandles);

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

    $self->_setError($self->{LAST_RESULT}{stderr});

    return (
        $self->{LAST_RESULT}{stdout},
        $self->{LAST_RESULT}{stderr},
        $self->{LAST_RESULT}{exit},
        $self->{LAST_RESULT}{error},
    );
}

sub buildSshCmd {
    my $self= shift;
    my $sCmd= shift;

    die "Peer.pm: No command specified!" unless defined $sCmd;
    die "Peer.pm: No host specified!" unless defined $self->getValue("host");

    my @sSshCmd= ('ssh');

    my $p= $self->getValue('port');
    push @sSshCmd, '-p', $p if $p;
    $p= $self->getValue("protocol") || '';
    push @sSshCmd, "-$p" if $p eq '1' || $p eq '2';
    push @sSshCmd, map {('-i', $_)} $self->resolveObjects("identity_files");
#    push @sSshCmd, '-vvv' if $self->{DEBUG};

    push @sSshCmd, $self->getUserHost();
    push @sSshCmd, $sCmd;
    return scalar $self->ShellQuote(@sSshCmd);
}

sub _runSshCmd {
    my $self= shift;
    my $sCmd= shift;
    my $hHandles= shift || {};

    my $sRunCmd= '';

    $sRunCmd= $self->buildSshCmd($sCmd);
    print "SSH: running [$sRunCmd]\n" if $self->{DEBUG};

    print "WARNING: Trying to access remote host \"" . $self->getValue("host") . "\"!\n" if $self->getSwitch("warn_on_remote_access");

    return $self->_runLocalCmd($sRunCmd, $hHandles);
}

# evaluates perl script remote or locally
sub runPerl {
    my $self= shift;
    my $sPerlScript= shift;
    my $refInVars= shift || {}; # input vars have to be references or skalars
    my $sOutVar= shift;
    my $hHandles= shift || {};

    die "Rabak::Peer->runPerl() may not have an output variable defined and a handle for STDOUT"
        . " at the same time!" if $sOutVar && exists $hHandles->{STDERR};

    # run script as command if it's remote or STDIN/STDOUT handles are defined
    # (will be "eval"ed otherwise)
    my $bRunAsCommand= scalar %$hHandles || $self->isRemote();

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
    # ATTENTION: script has to end with "__END__\n" to make remaining input parsed as stdin
    $sPerlScript= "
        use Data::Dumper;
        $sPerlVars
        $sPerlScript
        $sPerlDump
        __END__\n";

    if ($self->{DEBUG}) {
        # extract script name (is comment in first line)
        my $sScriptName= '';
        $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\s*\#\s*(\w+)\s?\(\s*\)\s*$//m;

        print "************* SCRIPT$sScriptName START ***************\n",
            "$sPerlScript\n",
            "************** SCRIPT$sScriptName END ****************\n";
    }

    # now execute script
    my $result;
    if ($bRunAsCommand) {
        my $fStdIn= $hHandles->{STDIN};
        my @sScript= ($sPerlScript);
        # if stdin is a scalar, simply append append text after __END__
        unless (ref $fStdIn) {
            push @sScript, $hHandles->{STDIN};
            $fStdIn= undef;
        }
        $hHandles->{STDIN}= sub {
            return shift @sScript if scalar @sScript;
            return $fStdIn->() if $fStdIn;
            return undef;
        };
        $self->runCmd('perl', $hHandles);
        $self->_setError($self->{LAST_RESULT}{stderr});
        print 'ERR: ' . $self->{LAST_RESULT}{stderr} . "\n" if $self->{DEBUG} && $self->{LAST_RESULT}{stderr};
        $result= $self->{LAST_RESULT}{exit} ? undef : $self->{LAST_RESULT}{stdout};
    }
    else {
        $result= eval $sPerlScript;
        if ($@) {
            $self->_setError($@);
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
sub _getDir {
    my $self= shift;
    my $sPath= $self->getPath(shift);
    my $bFileType= shift;

    my $sPerlScript= '
        # _getDir()
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

    return @{$self->runPerl($sPerlScript, {
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
        $self->runPerl(
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
    my %hParams= @_;

    return $sFile unless $self->isRemote();
    
    my ($fh, $sTmpName) = $self->localTempfile(%hParams);
    my $hHandles= {
        STDOUT => sub {
            print $fh @_;
        },
        STDOUT_UNBUFFERED => 1,
    };
    $self->_savecmd(scalar $self->ShellQuote('cat', $sFile), $hHandles);
    CORE::close $fh;
    return $sTmpName;
}

# copies a local (temp) file to the remote host
sub copyLocalFileToRemote {
    my $self= shift;
    my $sLocFile= shift;
    my $sRemFile= $self->getPath(shift);
    my %hParams= @_;

    $self->_setError();
    
    die 'Internal error: Parameters "APPEND" and "SAVE_COPY" are exclusive!' if $hParams{APPEND} && $hParams{SAVE_COPY};

    my $sqLocFile= $self->ShellQuote($sLocFile);
    my $sqRemFile= $self->ShellQuote($sRemFile);
    my $sCmdAppend= '';
    if ($hParams{SAVE_COPY}) {
        # if SAVE_COPY is given first copy to temporary file and rename on success 
        my $sqFinalRemote= $sqRemFile;
        my (undef, $sPath, $sFile)= File::Spec->splitpath($sRemFile);
        $sRemFile= $self->tempfile(DIR => $sPath, SUFFIX => ".$sFile");
        $sqRemFile= $self->ShellQuote($sRemFile);
        # rename file, preserve result and remove leftovers (if any)
        $sCmdAppend= " && mv -f $sqRemFile $sqFinalRemote; result=\$?; test -f $sqRemFile && rm $sqRemFile; exit \$result";
    }

    unless ($self->isRemote()) {
        $sLocFile= $self->getPath($sLocFile);
        $sqLocFile= $self->ShellQuote($sLocFile);
        return 1 if $sLocFile eq $sRemFile;
        if ($hParams{APPEND}) {
            $self->_setError(`cat $sqLocFile 2>&1 >> $sqRemFile`);
        }
        else {
            $self->_setError(`cp -f $sqLocFile $sqRemFile 2>&1 $sCmdAppend`);
        }
        return $self->getError ? 0 : 1;
    }

    my $fh;
    if (CORE::open $fh, $sLocFile) {
        my $sPipe= $hParams{APPEND} ? '>>' : '>';
        my $iBufferSize= 10240;

        my $hHandles= {
            STDIN => sub {
                my $sData;
                return $sData if read $fh, $sData, $iBufferSize;
                return undef;
            }
        };

        my ($stdout, $stderr, $exit) = $self->_runSshCmd("cat - $sPipe $sqRemFile $sCmdAppend", $hHandles);

        $self->_setError($stderr);
        CORE::close $fh;
        return $stderr ? 0 : 1;
    }
    $self->_setError("Could not open local file \"$sLocFile\"");
    return 0;
}

sub mkdir {
    my $self= shift;
    my $sPath= $self->getPath(shift);
    
    return 1 if $self->pretend();

    return ${$self->runPerl('
            # mkdir()
            my @sDirToDo= split /\//, $sPath;
            my @sDir= ();
            $result= 1;
            while (scalar @sDirToDo) {
                push @sDir, shift(@sDirToDo);
                my $sDir= join "/", @sDir;
                next unless $sDir;
                $result= -d $sDir || CORE::mkdir $sDir;
                last unless $result;
            }
        ', { "sPath" => $sPath }, '$result'
    ) || \undef};
}

# creates file if it doesn't exist
sub createFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);
    
    return 1 if $self->pretend();

    return ${$self->runPerl('
            # touch()
            my $fh;
            $result= -e $sFile || CORE::open $fh, ">$sFile";
        ', { "sFile" => $sFile }, '$result'
    ) || \undef};
}

sub symlink {
    my $self= shift;
#    my $sOrigFile= $self->getPath(shift);
    my $sOrigFile= shift;
    my $sSymLink= $self->getPath(shift);

    return ${$self->runPerl('
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

    return ${$self->runPerl('
            # unlink()
            $result= CORE::unlink $sFile;
        ', { "sFile" => $sFile, }, '$result'
    ) || \undef};
}

sub df {
    my $self= shift;
    my $sDir= $self->getPath(shift);
    my @sParams= @_;

    return $self->_savecmd(scalar $self->ShellQuote('df', @sParams, $sDir));
}

sub du {
    my $self= shift;
    my $sDir= $self->getPath(shift);
    my @sParams= @_;

    return $self->_savecmd(scalar $self->ShellQuote('du', @sParams, $sDir));
}

sub isDir {
    my $self= shift;
    my $sDir= $self->getPath(shift);

    return ${$self->runPerl('
            # isDir()
            $result= -d $sDir;
        ', { 'sDir' => $sDir, }, '$result'
    ) || \undef};
}

sub isReadable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->runPerl('
            # isReadable()
            $result= -r $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub isWritable {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->runPerl('
            # isWritable()
            $result= -w $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub isFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->runPerl('
            # isFile()
            $result= -f $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub _isSymlink {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return ${$self->runPerl('
            # _isSymlink()
            $result= -l $sFile;
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

# absPath *MUST NOT* use getPath!! would result in an infinte loop
sub absPath {
    my $self= shift;
    my $sFile= shift || '.'; # !! path *NOT* relative to target path but to cwd
    
    return ${$self->runPerl('
            # absPath()
            use Cwd;
            $result= Cwd::abs_path($sFile);
        ', { 'sFile' => $sFile, }, '$result'
    ) || \undef};
}

sub glob {
    my $self= shift;
    my $sFile= shift;

    return @{$self->runPerl('
            # glob()
            @result= glob($sFile);
        ', { 'sFile' => $sFile, }, '@result'
    ) || []};
}

sub rename {
    my $self= shift;
    my $sOldFile= shift;
    my $sNewFile= shift;

    return ${$self->runPerl('
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

    $self->_savecmd('cat - >> ' . $self->ShellQuote($sFile), $hHandles);
}

sub cat {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $self->_savecmd(scalar $self->ShellQuote('cat', $sFile));
}

sub mount {
    my $self= shift;
    my @sParams= @_;

    return $self->_savecmd(scalar $self->ShellQuote('mount', @sParams));
}

sub umount {
    my $self= shift;
    my @sParams= @_;

    return $self->_savecmd(scalar $self->ShellQuote('umount', @sParams));
}

sub rsync {
    my $self= shift;
    my %params= @_;
    
    my @sSourceFiles= ref $params{source_files} ? @{ $params{source_files} } : ($params{source_files});
    my $sTargetPath= $params{target_path};
    my $oTargetPeer= $params{target_peer};
    my @sRsyncOpts= @{ $params{opts} || [] };
    my $hIoHandles= $params{handles} || {};
    
    # $oSshPeer contains ssh parameters for rsync (seen from $oRsyncPeer)
    # - is $oTargetPeer if target is remote (rsync will be run on self)
    # - is $self if target is local and source is remote (rsync will be run locally)
    # $oRsyncPeer contains peer rsync is running from
    # - is $oTargetPeer if target is local and source is remote
    # - is $self otherwise
    my $oSshPeer;
    my $oRsyncPeer = $self;
    my $sSourceDirPref = "";
    my $sTargetDirPref = "";
    if ($oTargetPeer->isRemote()) {
        # unless target and source on same host/user/port
        unless ($oTargetPeer->getUserHostPort() eq $self->getUserHostPort()) {
            $oSshPeer = $oTargetPeer;
            $sTargetDirPref= $oTargetPeer->getUserHost(":");
        }
    }
    elsif ($self->isRemote()) {
        $oSshPeer= $self;
        $sSourceDirPref= $self->getUserHost(":");
        $oRsyncPeer = $oTargetPeer;
    }
    if ($oSshPeer) {
        my $sPort= $oSshPeer->getValue("port") || 22;
        my $sTimeout= $oSshPeer->getValue("timeout") || 150;
        my $sBandwidth= $oSshPeer->getValue("bandwidth") || '';
        my @sIdentityFiles= $oSshPeer->getValue("identity_files") ? split(/\s+/, $oSshPeer->getValue("identity_files")) : undef;

        my @sSshCmd= (
            'ssh',
            '-p', $sPort,
        );
        my $sSshCmd= "ssh -p $sPort";
        push @sSshCmd, map { ('-i', $_) } grep {$_} @sIdentityFiles;
        if ($oSshPeer->getValue("protocol")) {
            push @sSshCmd, '-1' if $oSshPeer->getValue('protocol') eq '1';
            push @sSshCmd, '-2' if $oSshPeer->getValue('protocol') eq '2';
        }
        push @sRsyncOpts, '--rsh=' . $self->ShellQuote(@sSshCmd), "--timeout=$sTimeout", '--compress';
        push @sRsyncOpts, "--bwlimit=$sBandwidth" if $sBandwidth;
    }

    my $sRsyncCmd= scalar $self->ShellQuote('rsync', @sRsyncOpts, (map {$sSourceDirPref . $self->getPath($_)} @sSourceFiles), $sTargetDirPref . $oTargetPeer->getPath($sTargetPath));

    if ($params{log_level}) {
        logger->log([$params{log_level}, "Running" .
            ($oRsyncPeer->isRemote() ?
                " on '" . $oRsyncPeer->getUserHostPort() . "'" :
                "") .
            ": $sRsyncCmd"]);
        logger->incIndent();
    }

    # run rsync command
    my (undef, undef, $iExit, $sError)= $oRsyncPeer->runCmd($sRsyncCmd, $hIoHandles);

    if ($params{log_level}) {
        logger->decIndent();
        logger->log([$params{log_level}, "rsync finished successfully"]) unless $iExit;
    }
    logger->error($sError) if $sError;
    logger->warn("rsync exited with result $iExit") if $iExit;
    return $iExit || 0;
}

sub tempfile {
    my $self= shift;
    my %hParams= @_;
    
    my $sSuffix= $hParams{SUFFIX} || '';
    my $sDir= $hParams{DIR} || $self->getValue("tempdir");

    $self= $self->new() unless ref $self;
    my $sFileName= ${$self->runPerl('
            # tempfile
            use File::Temp;
            use File::Spec;
            $sDir= File::Spec->tmpdir() unless $sDir;
            my $tempfh= File::Temp->new(
                "rabak-XXXXXX", UNLINK => 0, DIR => $sDir, SUFFIX => $sSuffix,
            );
            $tempfh->close();
            $sFileName= $tempfh->filename();
        ', { 'sDir' => $sDir, 'sSuffix' => $sSuffix, }, '$sFileName',
    ) || \undef};
    push @{$self->{TEMPFILES}}, $sFileName if $sFileName;
    return $sFileName;
}

sub tempdir {
    my $self= shift;
    my %hParams= @_;
    
    $self= $self->new() unless ref $self;
    my $sDir= $hParams{DIR} || $self->getValue("tempdir");
    my $sDirName= ${$self->runPerl('
            # tempdir
            use File::Temp;
            use File::Spec;
            $sDir= File::Spec->tmpdir() unless $sDir;
            $sDirName= File::Temp->newdir("rabak-XXXXXX", CLEANUP => 0, DIR => $sDir,);
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
    return $self->_savecmd("if [ -e $sTree ]; then rm -rf $sTree; fi");
}

=back

=cut

1;
