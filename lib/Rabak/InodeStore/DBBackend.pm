package Rabak::InodeStore::DBBackend;

use warnings;
use strict;

use DBI;
use Data::Dumper;
use File::Temp;
use File::Copy;
use Rabak::Log;

my %TableDefinitions= (
    'inodes' => 'inode INTEGER PRIMARY KEY, size INTEGER, mode INTEGER, owner TEXT, mtime INTEGER, digest TEXT',
    'files_inode' => 'inode INTEGER, filename TEXT PRIMARY KEY',
);
my %IndexDefinitions= (
    'inodes' => [
        {'name' => 'inodes_size', 'fields' => ['size']},
        {'name' => 'inodes_size_key', 'fields' => ['size', 'mode', 'owner', 'mtime']},
    ],
    'files_inode' => [
        {'name' => 'files_inode_inode', 'fields' => ['inode']},
    ],
);

sub new {
    my $class= shift;
    my $sFileName= shift;
    my $sDbEngine= shift || 'sqlite3';
    my $sTempDir= shift;
    my $hData= shift || {};
    
    my $sRealFileName= $sFileName;
    if ($sTempDir) {
        $sRealFileName =~ s/.*\///;
        (undef, $sRealFileName)= File::Temp::tempfile("${sRealFileName}XXXXXX",
            SUFFIX => ".db",
            DIR => $sTempDir,
            UNLINK => 1,
        );
        if (-e $sFileName) {
            copy($sFileName, $sRealFileName) or $sRealFileName= $sFileName;
        }
    }
    
    my $self= {
        dbfn=> $sFileName,
        real_dbfn=> $sRealFileName,
        dbh=> undef,
        db_backend=> $sDbEngine,
        is_valid=> 1,
        _tables=> {},
        
        _data=> $hData,
        
        db_sth=> {},
##        debug=> 1,

        _transaction_mode=> undef,
        _changed=> 0,
        
        cached_queries=> {},
        _cache_count=> 0,
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

sub getRealFileName {
    my $self= shift;
    
    return $self->{real_dbfn};
}

sub wasChanged {
    my $self= shift;
    return $self->{_changed};
}

sub getHandle {
    my $self= shift;
    
    unless ($self->{dbh}) {
        my $sFileName= $self->getRealFileName();
        $self->{dbh}= $self->createHandle($sFileName),
    }
    return $self->{dbh};
}

sub createHandle {
    my $self= shift;
    my $dbfn= shift;
    
    my %validDbBackends= (
        sqlite2 => "SQLite2",
        sqlite3 => "SQLite",
    );
    unless ($validDbBackends{$self->{db_backend} || ''}) {
        warn "Invalid database engine '$self->{opts}{db_backend}'." if $self->{db_backend};
        $self->{db_backend}= "sqlite3";
    }
    my $sDbBackend= $validDbBackends{$self->{db_backend}};

    $self->{is_new}= ! -f $dbfn || -z $dbfn;
    my $dbh= undef;
    eval {
        $dbh = DBI->connect("dbi:$sDbBackend:dbname=$dbfn", "", "")
            || die $DBI::errstr;
    };
    die "Could not create database '$dbfn'!\n$@" if $@;
    return $dbh;
}

sub _initTables {
    my $self= shift;
    my @sTableNames= @_;
    
    my $dbh= $self->getHandle();
    for my $sTableName (@sTableNames) {
        next if $self->{_tables}{$sTableName};
        die "Table name \"$sTableName\" is not valid." unless $TableDefinitions{$sTableName};
        $dbh->do("CREATE TABLE IF NOT EXISTS $sTableName ($TableDefinitions{$sTableName})");
        $self->{_tables}{$sTableName}= 1;
    }
    $self->commitTransaction();
}

sub _createIndices {
    my $self= shift;
    
    my $dbh= $self->getHandle();
    for my $sTableName (keys %{$self->{_tables}}) {
        next unless $IndexDefinitions{$sTableName};
        for my $hIndexDef (@{$IndexDefinitions{$sTableName}}) {
            $dbh->do("CREATE INDEX IF NOT EXISTS " . $hIndexDef->{name} . " ON $sTableName (" . join(', ', @{$hIndexDef->{fields}}) . ")");
        }
    }
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

sub execChangeQuery {
    my $self= shift;
    my $sQueryMode= shift;
    my $sQuery= shift;
    my @sValues= @_;

    if ($self->{cached_queries}) {
        $self->flushCache() if $self->{_cache_count} > 100;
        $self->{cached_queries}{$sQueryMode}{$sQuery}= [] unless $self->{cached_queries}{$sQueryMode}{$sQuery};
        push @{$self->{cached_queries}{$sQueryMode}{$sQuery}}, [@sValues];
        $self->{_cache_count}++;
    }
    else {
        $self->beginTransaction();
        return $self->execQuery($sQueryMode, $sQuery, @sValues);
    }
}

sub flushCache {
    my $self= shift;

    return unless $self->{cached_queries} && $self->{_cache_count};

    $self->beginTransaction();
    for my $sQueryMode (keys %{$self->{cached_queries}}) {
        for my $sQuery (keys %{$self->{cached_queries}{$sQueryMode}}) {
            my $aValues= undef;
            while ($aValues= shift @{$self->{cached_queries}{$sQueryMode}{$sQuery}}) {
                $self->execQuery($sQueryMode, $sQuery, @$aValues);
            }
        }
    }
    $self->{_cache_count}= 0;

}

sub execUpdate {
    my $self= shift;
    my $sQuery= shift;
    my @sValues= @_;

    return $self->execChangeQuery("update", $sQuery, @sValues);
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

#print Dumper($self->{db_sth});

    for my $sMode (@sModes) {
        next unless defined $self->{db_sth}{$sMode};
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
    
    return $self->execUpdate(
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
    
    return $self->execUpdate(
        "INSERT OR REPLACE INTO inodes (inode, size, mode, owner, mtime) VALUES (?, ?, ?, ?, ?)",
        $iInode, $iSize, $iMode, $sOwner, $iMtime,
    );
}

sub getInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execSelectOne(
        "SELECT * FROM inodes WHERE inode = ?",
        $iInode,
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

    my $result= {};
    
    my $sth= $self->prepareQuery("select", "SELECT inode, size, mode, owner, mtime FROM inodes");
    $sth->execute();
    while (my $row= $sth->fetchrow_arrayref()) {
        $row= [@$row];
        my $sKey= shift @$row;
        $result->{$sKey}= join "_", @$row;
    }
    return $result;
}

sub getInodeDigest {
    my $self= shift;
    my $iInode= shift;
    
    return $self->execSelectOne(
        "SELECT digest FROM inodes WHERE inode = ?",
        $iInode,
    );
}

sub setInodeDigest {
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
    
    return $self->execUpdate(
        "DELETE FROM inodes WHERE inode = ?",
        $iInode,
    );
}

sub removeFile {
    my $self= shift;
    my $sFileName= shift;
    
    return $self->execUpdate(
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
        my ($sFileName, $sRealFileName)= ($self->getFileName(), $self->getRealFileName());

        $self->{cached_queries}= undef unless $self->{is_valid};

        $self->endCached();
        # finish statements before commit
        $self->finishStatements();
    
        $self->commitTransaction($buildIndex);
    
        for my $sth (@{$self->getHandle()->{ChildHandles}}) {
            next unless defined $sth;
            logger->error("unresolved statement: '$sth->{Statement}' ($self->{dbfn})");
        }
    
        $self->getHandle()->disconnect();
        $self->{dbh}= undef;
        if ($self->{is_valid}) {
            unless ($sFileName eq $sRealFileName) {
                copy($sRealFileName, $sFileName) or logger->error("Could not update database file '$sFileName'");
            }
        }
        else {
            logger->error("Database file '$sFileName' is invalid. Deleting.");
            -f $sFileName && unlink $sFileName;
            -f $sRealFileName && unlink $sRealFileName;
        }
    }
    return undef;
}

sub invalidate {
    my $self= shift;
    
    $self->{is_valid}= 0;
}

sub beginCached {
    my $self= shift;
    
    return if $self->{cached_queries};
    $self->{cached_queries}= {};
}

sub endCached {
    my $self= shift;

    $self->flushCache();
    $self->{cached_queries}= undef;
}

sub beginTransaction {
    my $self= shift;
    
    return if $self->{_transaction_mode};
    
    $self->getHandle()->begin_work();
    $self->{_transaction_mode}= 1;
    $self->{_changed}= 1;
}

sub commitTransaction {
    my $self= shift;
    my $buildIndex= shift;
    $buildIndex= 1 unless defined $buildIndex;
    
    $self->endCached();
    
    return unless $self->{_transaction_mode} && $self->{dbh};
    
    # free statement handles
    $self->finishStatements("update");

    $self->getHandle()->commit();
    
    # creating indices after inserting all data
    $self->_createIndices() if $buildIndex;
  
    $self->{_transaction_mode}= undef;
}

sub unlink {
    my $self= shift;
    
    $self->endWork(0);
    
    my $sFileName= $self->getFileName();
    unlink $sFileName if $sFileName && -f $sFileName;
}

1;
