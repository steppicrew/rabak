package DupMerge::DataStore::DataStoreDBBackend;

use warnings;
use strict;

sub new {
    my $class= shift;
    my $sFileName= shift;
    my $sDbEngine= shift || 'sqlite3';
    my $hData= shift || {};
    
    my $self= {
        dbfn=> $sFileName,
        dbh=> undef,
        db_engine=> $sDbEngine,
        is_new=> undef,
        
        _data=> $hData,
        
        db_sth=> {},
    };

    bless $self, $class;
}

sub getData {
    my $self= shift;
    my $sKey= shift;
    
    return $self->{_data}{$sKey};
}

sub setData {
    my $self= shift;
    my $sKey= shift;
    my $sValue= shift;
    
    $self->{_data}{$sKey}= $sValue;
}

sub getFileName {
    my $self= shift;
    
    return $self->{dbfn};
}

sub getHandle {
    my $self= shift;
    
    unless ($self->{dbh}) {
        my $sFileName= $self->getFileName();
        $self->{dbh}= $self->createHandle($sFileName),
    }
    return $self->{dbh};
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sKey= shift;
    my $sName= shift;
    
    $self->{db_sth}{insert}{inodefile}=
        $self->getHandle()->prepare("INSERT INTO files_inode (inode, key, filename) VALUES (?, ?, ?)") unless $self->{db_sth}{insert}{inodefile};
    
    $self->{db_sth}{insert}{inodefile}->execute($iInode, $sKey, $sName);
}

sub addInodeSize {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    my $iInode= shift;
    
    $self->{db_sth}{insert}{inodesize}=
        $self->getHandle()->prepare("INSERT INTO inodes (size, key, inode) VALUES (?, ?, ?)") unless $self->{db_sth}{insert}{inodesize};
    
    $self->{db_sth}{insert}{inodesize}->execute($iSize, $sKey, $iInode);
}

sub getDescSortedSizes {
    my $self= shift;
    
    return $self->getHandle()->selectcol_arrayref("SELECT DISTINCT size FROM inodes ORDER BY size DESC");
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    
    return $self->getHandle()->selectcol_arrayref("SELECT DISTINCT key FROM inodes WHERE size = ?",
        undef, $iSize);
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    
    return $self->getHandle()->selectcol_arrayref("SELECT inode FROM inodes WHERE size = ? AND key = ?",
        undef, $iSize, $sKey);
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->getHandle()->selectcol_arrayref("SELECT filename FROM files_inode WHERE inode = ?",
        undef, $iInode);
}

sub getKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    my @result= $self->getHandle()->selectrow_array("SELECT key FROM files_inode WHERE inode = ?",
        undef, $iInode);
    return $result[0] if @result;
    return undef;
}

sub getFileCount {
    my $self= shift;
    
    my @result= $self->getHandle()->selectrow_array("SELECT COUNT(filename) FROM files_inode");
    return $result[0] if @result;
    return undef;
}

sub getInodes {
    my $self= shift;
    
    return $self->getHandle()->selectcol_arrayref("SELECT inode FROM inodes");
}

sub getDigestByInode {
    my $self= shift;
    my $iInode= shift;
    
    my @result= $self->getHandle()->selectrow_array("SELECT digest FROM inodes WHERE inode = ?",
        undef, $iInode);
    return $result[0] if @result;
    return undef;
}

sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    $self->{db_sth}{insert}{inodedigest}=
        $self->getHandle()->prepare("UPDATE inodes SET digest = ? WHERE inode = ?") unless $self->{db_sth}{insert}{inodedigest};
    
    $self->{db_sth}{insert}{inodedigest}->execute($sDigest, $iInode);
}

sub removeInode {
    my $self= shift;
    my $iInode= shift;
    
    $self->{db_sth}{insert}{removeinode}=
        $self->getHandle()->prepare("DELETE FROM inodes WHERE inode = ?") unless $self->{db_sth}{insert}{removeinode};
    
    $self->{db_sth}{insert}{removeinode}->execute($iInode);
}

sub createHandle {
    my $self= shift;
    my $dbfn= shift;
    
    my %validDbEngines= (
        sqlite2 => "SQLite2",
        sqlite3 => "SQLite",
    );
    unless ($validDbEngines{$self->{db_engine} || ''}) {
        warn "Invalid database engine '$self->{opts}{db_engine}'." if $self->{db_engine};
        $self->{db_engine}= "sqlite3";
    }
    my $sDbEngine= $validDbEngines{$self->{db_engine}};

    $self->{is_new}= ! -f $dbfn;
    my $dbh= undef;
    eval {
        $dbh = DBI->connect("dbi:$sDbEngine:dbname=$dbfn", "", "")
            || die $DBI::errstr;
        if ($self->{is_new}) {
            $dbh->do("CREATE TABLE inodes (size INTEGER, key TEXT, inode INTEGER PRIMARY KEY, digest TEXT)");
            $dbh->do("CREATE TABLE files_inode (inode INTEGER, key TEXT, filename TEXT PRIMARY KEY)");
        }
    };
    die "Could not create database!\n$@" if $@;
    return $dbh;
}

sub beginWork {
    my $self= shift;

    # make sure database exists    
    $self->getHandle();
}

sub endWork {
    my $self= shift;
    
    if ($self->{dbh}) {
        $self->endInsert();
    
        # free statement handles
        for my $sth_mode (keys %{$self->{db_sth}}) {
            for my $sth_name (keys %{$self->{db_sth}{$sth_mode}}) {
                delete $self->{db_sth}{$sth_mode}{$sth_name};
            }
            delete $self->{db_sth}{$sth_mode};
        }
        
        $self->getHandle()->disconnect();
    }
    return undef;
}

sub beginInsert {
    my $self= shift;
    
    return if $self->{_insert_mode};
    
    $self->getHandle()->begin_work();
    $self->{_insert_mode}= 1;
}

sub endInsert {
    my $self= shift;
    
    return unless $self->{_insert_mode} && $self->{dbh};
    
    $self->getHandle()->commit();
    
    # free insert statement handles
    if ($self->{db_sth}{insert}) {
        for my $sth_name (keys %{$self->{db_sth}{insert}}) {
            delete $self->{db_sth}{insert}{$sth_name};
        }
    }

    # creating indices after inserting all data
    if ($self->{is_new}) {
        $self->getHandle()->do("CREATE INDEX inodes_size ON inodes (size)");
        $self->getHandle()->do("CREATE INDEX inodes_size_key ON inodes (size, key)");
        $self->getHandle()->do("CREATE INDEX files_inode_inode ON files_inode (inode)");
    }
  
    $self->{_insert_mode}= undef;
}

sub unlink {
    my $self= shift;
    
    my $sFileName= $self->getFileName();
    unlink $sFileName if $sFileName && -f $sFileName;
}

1;
