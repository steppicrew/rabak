#!/usr/bin/perl

package RabakLib::Type;

use warnings;
use strict;

use File::Temp ();

# use Rabak::ConfFile;

# use vars qw(@ISA);

sub new {
    my $class = shift;
    my $oSet= shift;
    my $self= {
        '.ERRORCODE' => 0,
        '.DEBUG' => 0,
        SET => $oSet,
    };
    bless $self, $class;
}

sub get_bakset_target {
    my $self= shift;
    return File::Spec->rel2abs($self->get_value('target'));
}

sub collect_bakdirs {
    my $self= shift;
    my $sSubSetBakDay= shift || 0;

    my $sBakSet= $self->get_value('name');
    my $sBakDir= $self->get_bakset_target();
    my @sBakDir= ();
    my $sSubSet= '';

    while (<$sBakDir/*>) {
        next unless /^$sBakDir\/(.*)/;
        my $sMonthDir= $1;

        next unless -d "$sBakDir/$sMonthDir" && $sMonthDir =~ /^(\d\d\d\d\-\d\d)\.($sBakSet)$/;

        while (<$sBakDir/$sMonthDir/*>) {
            next unless /^$sBakDir\/$sMonthDir\/(.*)/;
            my $sDayDir= $1;
            # print "$sDayDir??\n";
            next unless -d $_ && $sDayDir =~ /^(\d\d\d\d\-\d\d\-\d\d)([a-z])?\.($sBakSet)$/;
            if ($sSubSetBakDay eq $1) {
                die "Maximum of 27 backups reached!" if $2 && $2 eq 'z';
                if (!$2) {
                    $sSubSet= 'a' if $sSubSet eq '';
                }
                else {
                    $sSubSet= chr(ord($2)+1) if $sSubSet le $2;
                }
            }
            push @sBakDir, "$sBakDir/$sMonthDir/$sDayDir";
            # print "$sDayDir\n";
        }
    }

    @sBakDir= sort { $b cmp $a } @sBakDir;

    unshift @sBakDir, $sSubSet if $sSubSetBakDay;

    return @sBakDir;
    # return wantarray ? (\$sBakDir, $sSubSet) : \$sBakDir;
}

sub get_value {
    my $self= shift;
    return $self->{SET}->get_value(@_);
}

sub xerror {
    my $self= shift;
    return $self->{SET}->xerror(@_);
}

sub xlog {
    my $self= shift;
    return $self->{SET}->xlog(@_);
}

sub tempfile {
    return @_= File::Temp->tempfile('rabak-XXXXXX', UNLINK => 1, DIR => File::Spec->tmpdir);
}

sub valid_source_dir {
    my $self= shift;

    my $sSourceDir= File::Spec->rel2abs($self->get_value('source'));

    if (!-d $sSourceDir) {
        $self->xerror("Source \"$sSourceDir\" is not a directory. Backup set skipped.");
        return undef;
    }
    if (!-r $sSourceDir) {
        $self->xerror("Source \"$sSourceDir\" is not readable. Backup set skipped.");
        return undef;
    }

    return $sSourceDir;
}

1;