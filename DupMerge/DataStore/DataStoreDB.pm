package DupMerge::DataStoreDB;

use warnings;
use strict;

use vars qw(@ISA);

@ISA = qw(DupMerge::DataStore);

use File::Temp ();

sub new {
    my $class= shift;
    my $sTempDir= shift;
    
    my $self= $class->SUPER::new();

    eval {
        $self->{temp_dir}= File::Temp::tempdir(DIR => $sTempDir, CLEANUP => 1);
        $self->{dbfn}= "$self->{temp_dir}/inode_size.db";
        $self->{dbh} = DBI->connect("dbi:SQLite2:dbname=$self->{dbfn}", "", "")
            || $DBI::errstr;
        $self->{dbh}->do("CREATE TABLE size (size INTEGER, key TEXT, inode INTEGER)");
        $self->{dbh}->do("CREATE TABLE inodes (inode INTEGER, key TEXT, filename TEXT)");
    };
    die "Could not create database!\n$@" if $@;
    
    bless $self, $class;
}

sub destroy {
    my $self= shift;
    
    if ($self->{dbh}) {
        $self->{dbh}->disconnect();
        delete $self->{dbh};
        unlink $self->{dbfn};
        delete $self->{dbfn};
    }
    return $self->SUPER::destroy();
}

sub addInodeFile {
    my $self= shift;
    my $iInode= shift;
    my $sKey= shift;
    my $sName= shift;
    
    $self->SUPER::addInodeFile($iInode, $sKey, $sName);
    
    $self->{db_sth_inodefile}=
        $self->{dbh}->prepare("INSERT INTO inodes (inode, key, filename) VALUES (?, ?, ?)") unless $self->{db_sth_inodefile};
    
    $self->{db_sth_inodefile}->execute($iInode, $sKey, $sName);
}

sub addInodeSize {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    my $iInode= shift;
    
    $self->{db_sth_inodesize}=
        $self->{dbh}->prepare("INSERT INTO size (size, key, inode) VALUES (?, ?, ?)") unless $self->{db_sth_inodesize};
    
    $self->{db_sth_inodesize}->execute($iSize, $sKey, $iInode);
}

sub getDescSortedSizes {
    my $self= shift;
    
    return $self->{dbh}->selectcol_arrayref("SELECT DISTINCT size FROM size ORDER BY size DESC");
}

sub getKeysBySize {
    my $self= shift;
    my $iSize= shift;
    
    return $self->{dbh}->selectcol_arrayref("SELECT DISTINCT key FROM size WHERE size = ?",
        undef, $iSize);
}

sub getInodesBySizeKey {
    my $self= shift;
    my $iSize= shift;
    my $sKey= shift;
    
    return $self->{dbh}->selectcol_arrayref("SELECT inode FROM size WHERE size = ? AND key = ?",
        undef, $iSize, $sKey);
}

sub getFilesByInode {
    my $self= shift;
    my $iInode= shift;
    
    return $self->{dbh}->selectcol_arrayref("SELECT filename FROM inodes WHERE inode = ?",
        undef, $iInode);
}

sub getKeyByInode {
    my $self= shift;
    my $iInode= shift;
    
    my @result= $self->{dbh}->selectrow_array("SELECT key FROM inodes WHERE inode = ?",
        undef, $iInode);
    return $result[0] if @result;
    return undef;
}

sub beginWork {
    my $self= shift;
    
    $self->{dbh}->begin_work();
}

sub endWork {
    my $self= shift;
    
    $self->{dbh}->commit();
    
    # creating indices after inserting all data
    $self->{dbh}->do("CREATE INDEX size_size ON size (size)");
    $self->{dbh}->do("CREATE INDEX size_size_key ON size (size, key)");
    $self->{dbh}->do("CREATE INDEX inodes_inode ON inodes (inode)");
}

1;
