#!/usr/bin/perl

package RabakLib::Peer;

# wrapper class to exceute commands remotely or locally

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(RabakLib::Conf);

use Data::Dumper;
use File::Spec ();
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
    $self->{TEMP_RT_ENV}= undef;

    bless $self, $class;

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

# delete all non deleted temp files on exit (important for remote sessions)
sub DESTROY {
    my $self= shift;

# TODO: cleanup may create new object -> raises warning
#    $self->cleanupTempfiles();
}

sub cleanupTempfiles {
    my $self= shift;

    for my $sTempFile (@{$self->{TEMPFILES}}) {
        $self->rmtree($sTempFile);
    }
    $self->{TEMPFILES}= [];
}

sub local_tempfile {
    my $self= shift;

#    $self= $self->new() unless ref $self;
    my $sDir= File::Spec->tmpdir;
#    $sDir = $self->get_value("tempdir");

    return @_= File::Temp->tempfile("rabak-XXXXXX", UNLINK => 1, DIR => $sDir);
}

sub local_tempdir {
    my $self= shift;
    
    my $sDir= File::Spec->tmpdir;
#    my $sDir= $self->get_value("tempdir");
    my $sDirName= File::Temp->tempdir("rabak-XXXXXX", CLEANUP => 1, DIR => $sDir);

    return $sDirName;
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

    return $self->_run_ssh_cmd($cmd, undef, $hHandles) if $self->is_remote();
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

    push @sSshCmd, '-p', $self->get_value("port") if $self->get_value("port");
    if ($self->get_value("protocol")) {
        push @sSshCmd, '-1' if $self->get_value("protocol") eq "1";
        push @sSshCmd, '-2' if $self->get_value("protocol") eq "2";
    }
    push @sSshCmd, '-i', $self->resolveObjects("identity_files") if $self->get_value("identity_files");
#    push @sSshCmd, '-vvv' if $self->{DEBUG};

    push @sSshCmd, $self->getUserHost();
    push @sSshCmd, $sCmd;
    $_= $self->shell_quote($_) for (@sSshCmd);
    return join(" ", @sSshCmd);
}

# quote "'" char for shell execution
sub shell_quote {
    my $self= shift;
    my $sVal= shift;
    my $bDontEnclose= shift;
    $sVal =~ s/\'/\'\\\'\'/g;
    return "'$sVal'" unless $bDontEnclose;
    return $sVal;
}

sub _run_ssh_cmd {
    my $self= shift;
    my $sCmd= shift;
    my $sStdIn= shift;
    my $hHandles= shift || {};

    my $sRunCmd= '';

    if (defined $sStdIn) {
        die "More than one STDIN defined!" if defined $hHandles->{STDIN};
        $hHandles->{STDIN}= $sStdIn;
    }
    
    $sRunCmd= $self->build_ssh_cmd($sCmd);
    print "SSH: stdin [$sStdIn]\n######################\n" if $self->{DEBUG} && defined $sStdIn;
    print "SSH: running [$sRunCmd]\n" if $self->{DEBUG};

    print "WARNING: Trying to access remote host \"" . $self->get_value("host") . "\"!\n" if $self->get_switch("warn_on_remote_access");

    return $self->_run_local_cmd($sRunCmd, $hHandles);
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
        $sPerlDump= "print " if $self->is_remote();
        $sPerlDump.= "Data::Dumper->Dump([\\$sOutVar], ['OUT_VAR']);";
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
        # extract script name
        my $sScriptName= "";
        $sScriptName= " \"$1\"" if $sPerlScript=~ s/^\s*\#\s*(\w+)\s?\(\s*\)\s*$//m;

        print "************* SCRIPT$sScriptName START ***************\n" .
            "$sPerlScript\n" .
            "************** SCRIPT$sScriptName END ****************\n";
    }

    # now execute script
    my $result;
    if ($self->is_remote()) {
        $result= $self->_sshperl($sPerlScript);
    }
    else {
        $result= eval $sPerlScript;
        $self->_set_error(join("\n", $@));
    }

    print "OUT: $result\n" if $self->{DEBUG} && $result;

    # extract scripts result (if everything was ok, eval($result) sets $OUT_VAR)
    my $OUT_VAR = \undef;
    eval($result) if $result && $sOutVar;
    return $OUT_VAR;
}

sub _sshperl {
    my $self= shift;
    my $sPerlScript= shift;

    $self->_run_ssh_cmd("perl", $sPerlScript);
    $self->_set_error($self->{LAST_RESULT}{stderr});
    print "ERR: " . $self->{LAST_RESULT}{stderr} . "\n" if $self->{DEBUG} && $self->{LAST_RESULT}{stderr};
    return $self->{LAST_RESULT}{exit} ? '' : $self->{LAST_RESULT}{stdout};
}

# builds an entire RabakLib directory structure on remote site
sub _buildTempRuntimeEnv {
    my $self= shift;
    
    return $self->{TEMP_RT_ENV} if defined $self->{TEMP_RT_ENV} && $self->isDir($self->{TEMP_RT_ENV});
    
    my $sTempDir= $self->tempdir();
    my $sModuleBase= __PACKAGE__;
    $sModuleBase=~ s/\:\:.*//;
    my @sRabakPaths= map {$INC{$_}} grep {/^$sModuleBase\//} keys %INC;
    unless (scalar @sRabakPaths) {
        logger->error("Could not determine ${sModuleBase}'s path!");
        return 0;
    }
    my $sBasePath= Cwd::abs_path($sRabakPaths[0]);
    $sBasePath=~ s/(\/$sModuleBase\/).*/$1/;

    return $sBasePath unless $self->is_remote();

    return undef if $self->copyLocalFilesToRemote(
        [$sBasePath],
        $sTempDir,
        1,
        sub {
            my $sVar= shift;
            $sVar=~ s/.*\/($sModuleBase\/)/$1/;
            $sVar;
        },
    );
    
    $self->{TEMP_RT_ENV}= $sTempDir;
    return $self->{TEMP_RT_ENV};
}

# runs given script with rabak environment
sub run_rabak_script {
    my $self= shift;
    my $sScript= shift;
    my $hHandles= shift || {};
    
    my $sRtDir= $self->_buildTempRuntimeEnv();
    my $sPerlCmd= 'perl';
    $sPerlCmd.= " -I'$sRtDir'" if $sRtDir;
    
    unless ($hHandles->{STDOUT}) {
        # initialize peer's logging, parse log output from peer and log here
        $sScript= '
        use RabakLib::Log;

        my $oConf= RabakLib::Conf->new();
        $oConf->set_value("switch.verbose", logger()->LOG_MAX_LEVEL);
        $oConf->set_value("switch.pretend", 0);
        $oConf->set_value("switch.quiet", 0);
        logger()->init($oConf);
        logger()->set_prefix("X");
        ' . $sScript if defined $sScript;

        # TODO: log file parsing should be done in RabakLib::Log
        my %logLevelPrefix= %{RabakLib::Log::logger()->LOG_LEVEL_PREFIX()};
        my %logPrefixLevel= map {quotemeta($logLevelPrefix{$_}) => $_} keys %logLevelPrefix;
        $hHandles->{STDOUT}= sub {
            foreach my $sLine (@_) {
                foreach my $sqPref (keys %logPrefixLevel) {
                    if ($sLine=~ s/^$sqPref\:\s*.*?\]\s//) {
                        RabakLib::Log::logger()->log([$logPrefixLevel{$sqPref}, $sLine]);
                        last;
                    }
                }
            }
        };
    }
    $hHandles->{STDERR}= sub {RabakLib::Log::logger()->error(@_)} unless $hHandles->{STDERR};
    $hHandles->{STDIN}= $sScript if defined $sScript;
    
    return $self->run_cmd($sPerlCmd, $hHandles);
}

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

    return %{$self->_saveperl($sPerlScript, {
            "sPath" => $sPath,
            "iLevel" => $iLevel,
        }, '%Dir'
    )};
}

# makes sure the given file exists locally
sub getLocalFile {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $sFile unless $self->is_remote();
    
    my ($fh, $sTmpName) = $self->local_tempfile;
    my $hHandles= {
        STDOUT => sub {
            print $fh @_;
        },
    };
    $self->savecmd("cat '$sFile'", $hHandles);
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
        return 1 if $sLocFile eq $sRemFile;
        if ($bAppend) {
            $self->_set_error(`cat "$sLocFile" 2>&1 >> "$sRemFile"`);
        }
        else {
            $self->_set_error(`cp -f "$sLocFile" "$sRemFile" 2>&1`);
        }
        return $self->get_error ? 0 : 1;
    }

    my $fh;
    if (CORE::open $fh, $sLocFile) {
        my $sPipe= $bAppend ? ">>" : ">";
        my $iBufferSize= 10240;

        my $hHandles= {
            STDIN => sub {
                my $sData;
                return $sData if read $fh, $sData, $iBufferSize;
                return undef;
            }
        };

        my ($stdout, $stderr, $exit) = $self->_run_ssh_cmd("cat - $sPipe " . $self->shell_quote($sRemFile), undef, $hHandles);

        $self->_set_error($stderr);
        CORE::close $fh;
        return $stderr ? 0 : 1;
    }
    $self->_set_error("Could not open local file \"$sLocFile\"");
    return 0;
}

# copies local (temp) files to the remote host (recursive optional)
sub copyLocalFilesToRemote {
    my $self= shift;
    my $sLocFiles= shift;
    my $sRemDir= $self->getPath(shift);
    my $bRecursive= shift;
    my $fAbs2Rel= shift || sub{$_[0]=~ s/.*\///; $_[0]}; # return basename by default

    while (my $sFile= shift @$sLocFiles) {
        my $sRelPath= $fAbs2Rel->($sFile);
        if (-d $sFile) {
            next unless $bRecursive;
            my $dh;
            if (opendir $dh, $sFile) {
                my @sNewFiles= map {"$sFile/$_"} grep {/\.pm$/ || (-d "$sFile/$_" && !/^\.\.?$/)} readdir $dh;
                closedir $dh;
                next unless scalar @sNewFiles;
                $self->mkdir("$sRemDir/$sRelPath");
                push @$sLocFiles, @sNewFiles;
            }
            else {
                logger->error("Could not read directory \"$sFile\"");
                return 1;
            }
            next;
        }
        next unless -f $sFile;
        $self->copyLocalFileToRemote($sFile, "$sRemDir/$sRelPath");
    }
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
    my $sFile= shift || '.'; # !! path *NOT* relative to target path but to cwd
    
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
        $self->savecmd("echo " .  $self->shell_quote($_) . " >> '$sFile'");
    }
}

sub cat {
    my $self= shift;
    my $sFile= $self->getPath(shift);

    return $self->savecmd("cat '$sFile'");
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

    $self= $self->new() unless ref $self;
    my $sDir= File::Spec->tmpdir;
#    $sDir = $self->get_value("tempdir");
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

    $self= $self->new() unless ref $self;
    my $sDir= File::Spec->tmpdir;
#    $sDir= $self->get_value("tempdir");
    my $sDirName= ${$self->_saveperl('
            # tempdir
            use File::Temp;
            $sDirName= File::Temp->tempdir("rabak-XXXXXX", CLEANUP => 0, DIR => $sDir);
        ', { "sDir" => $sDir, }, '$sDirName',
    )};
    push @{$self->{TEMPFILES}}, $sDirName;
    return $sDirName
}

sub rmtree {
    my $self= shift;
    my $sTree= $self->getPath(shift);

    die "RabakLib::Peer::rmtree called with dangerous parameter ($sTree)!" if $sTree eq '' || $sTree eq '/' || $sTree=~ /\*/;

    $self= $self->new() unless ref $self;
    return $self->savecmd("if [ -e '$sTree' ]; then rm -rf '$sTree'; fi");
    # TODO: why does this not work???
    return ${$self->_saveperl('
            # rmtree
            use File::Path;
            $result= rmtree($sTree, $bDebug);
        ', { sTree => $sTree, bDebug => $self->{DEBUG} }, '$result',
    )};
}

=back

=cut

1;
