package DupMerge::DataStore::DataStoreDBBackend;

use warnings;
use strict;

use DBI;
use Data::Dumper;

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
#        debug=> 1,
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
            $dbh->do("CREATE TABLE inodes (inode INTEGER PRIMARY KEY, size INTEGER, mode INTEGER, owner TEXT, mtime INTEGER, digest TEXT)");
            $dbh->do("CREATE TABLE files_inode (inode INTEGER, filename TEXT PRIMARY KEY)");
        }
    };
    die "Could not create database!\n$@" if $@;
    return $dbh;
}

sub prepareQuery {
    my $self= shift;
    my $sQueryMode= shift;
    my $sQuery= shift;
    
    $self->{db_sth}{$sQueryMode}{$sQuery}=
        $self->getHandle()->prepare($sQuery) unless $self->{db_sth}{$sQueryMode}{$sQuery};
    
    return $self->{db_sth}{$sQueryMode}{$sQuery};
}

sub debugQuery {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;

    print "executing '$sQuery' with values (" . join(", ", @sValues) . ") [$self->{dbfn}]\n";
}

sub execQuery {
    my $self= shift;
    my $sQueryMode= shift;
    my $sQuery= shift;
    my @sValues= @_;

    $self->debugQuery($sQuery, @sValues) if $self->{debug};    
    return $self->prepareQuery($sQueryMode, $sQuery)->execute(@sValues);
}

sub execInsert {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;
    $self->beginInsert();
    return $self->execQuery("insert", $sQuery, @sValues);
}

sub execUpdate {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;
    $self->beginInsert();
    return $self->execQuery("update", $sQuery, @sValues);
}

sub execDelete {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;
    $self->beginInsert();
    return $self->execQuery("delete", $sQuery, @sValues);
}

sub execSelectCol {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;

    $self->debugQuery($sQuery, @sValues) if $self->{debug};    
    
    return $self->getHandle()->selectcol_arrayref(
        $self->prepareQuery("select", $sQuery),
        undef, @sValues,
    );
}

sub execSelectRows {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;

    $self->debugQuery($sQuery, @sValues) if $self->{debug};    
    
    return $self->getHandle()->selectall_arrayref(
        $self->prepareQuery("select", $sQuery),
        { Slice => {} }, @sValues,
    );
    
}

sub execSelectOne {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;

    $self->debugQuery($sQuery, @sValues) if $self->{debug};    
    
    my $result= $self->getHandle()->selectrow_arrayref(
        $self->prepareQuery("select", $sQuery),
        undef, @sValues,
    );
    return undef unless defined $result;
    return $result->[0] if scalar @$result;
    return undef;
}

sub finishStatements {
    my $self= shift;
    my @sModes= @_ || keys %{$self->{db_sth}};

    for my $sMode (@sModes) {
        next unless $self->{db_sth}{$sMode};
        for my $sName (keys %{$self->{db_sth}{$sMode}}) {
            $self->{db_sth}{$sMode}{$sName}->finish();
            delete $self->{db_sth}{$sMode}{$sName};
        }
        delete $self->{db_sth}{$sMode};
    }
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;
    
    return $self->execInsert(
        "INSERT INTO files_inode (inode, filename) VALUES (?, ?)",
        $iInode, $sName,
    );
}

sub updateInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sName= shift;

    return $self->execUpdate(
        "UPDATE files_inode SET inode = ? WHERE filename = ?",
        $iInode, $sName,
    );
}

sub addInode {
    my $self= shift;
    my $iInode= shift;
    my $iSize= shift;
    my $iMode= shift;
    my $sOwner= shift;
    my $iMtime= shift;
    
    return $self->execInsert(
        "INSERT OR REPLACE INTO inodes (inode, size, mode, owner, mtime) VALUES (?, ?, ?, ?, ?)",
        $iInode, $iSize, $iMode, $sOwner, $iMtime,
    );
}

sub getDescSortedSizes {
    my $self= shift;
    
    return $self->execSelectCol("SELECT DISTINCT size FROM inodes ORDER BY size DESC");
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    my $aKeys= shift;
    
    $aKeys= ['size'] unless scalar @$aKeys;
    my $sQueryKey= join ", ", @$aKeys;
    return $self->execSelectRows(
        "SELECT DISTINCT $sQueryKey FROM inodes WHERE size = ?",
        $iSize,
    );
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $hKeys= shift;
    
    my $sQueryKey= "";
    my @KeyValues= ();
    for my $sKey (sort keys %$hKeys) {
        $sQueryKey.= " AND $sKey = ?";
        push @KeyValues, $hKeys->{$sKey};
    }

    return $self->execSelectCol(
        "SELECT inode FROM inodes WHERE size = ? $sQueryKey",
        $iSize, @KeyValues,
    );
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execSelectCol(
        "SELECT filename FROM files_inode WHERE inode = ?",
        $iInode,
    );
}

sub getFileKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execSelectOne(
        "SELECT key FROM files_inode WHERE inode = ?",
        $iInode,
    );
}

sub getFileCount {
    my $self= shift;
    
    return $self->execSelectOne(
        "SELECT COUNT(filename) FROM files_inode",
    );
}

sub getInodes {
    my $self= shift;
    
    return $self->execSelectCol(
        "SELECT inode FROM inodes",
    );
}

sub getDigestByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execSelectOne(
        "SELECT digest FROM inodes WHERE inode = ?",
        $iInode,
    );
}

sub setInodesDigest {
    my $self= shift;
    my $iInode= shift;
    my $sDigest= shift;
    
    return $self->execUpdate(
        "UPDATE inodes SET digest = ? WHERE inode = ?",
        $sDigest, $iInode,
    );
}

sub removeInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execDelete(
        "DELETE FROM inodes WHERE inode = ?",
        $iInode,
    );
}

sub removeFile {
    my $self= shift;
    my $sFileName= shift;
    
    return $self->execDelete(
        "DELETE FROM files_inode WHERE filename = ?",
        $sFileName,
    );
}

sub beginWork {
    my $self= shift;

    # make sure database exists    
    $self->getHandle();
}

sub endWork {
    my $self= shift;
    my $buildIndex= shift;
    
    if ($self->{dbh}) {
        $self->endInsert($buildIndex);
    
        # free statement handles
        $self->finishStatements();
        
        $self->getHandle()->disconnect();
    }
    return undef;
}

sub terminate {
    my $self= shift;
    $self->endWork(0);
}

sub beginInsert {
    my $self= shift;
    
    return if $self->{_insert_mode};
    
    $self->getHandle()->begin_work();
    $self->{_insert_mode}= 1;
}

sub endInsert {
    my $self= shift;
    my $buildIndex= shift;
    $buildIndex= 1 unless defined $buildIndex;
    
    return unless $self->{_insert_mode} && $self->{dbh};
    
    $self->getHandle()->commit();
    
    # free statement handles
    $self->finishStatements();

    # creating indices after inserting all data
    if ($buildIndex && $self->{is_new}) {
        $self->getHandle()->do("CREATE INDEX inodes_size ON inodes (size)");
        $self->getHandle()->do("CREATE INDEX inodes_size_key ON inodes (size, mode, owner, mtime)");
        $self->getHandle()->do("CREATE INDEX files_inode_inode ON files_inode (inode)");
        $self->{is_new}= undef;
    }
  
    $self->{_insert_mode}= undef;
}

sub unlink {
    my $self= shift;
    
    $self->endWork(0);
    
    my $sFileName= $self->getFileName();
    unlink $sFileName if $sFileName && -f $sFileName;
}

1;
