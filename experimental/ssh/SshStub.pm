package SshStub;

use strict;
use warnings;

sub Serialize {
    return sub {
        my $sData= shift;
        return "\x00\x00UNDEF\n" unless defined $sData;
        $sData=~ s/\x00/\x01\x00/g;

        # add an empty escape sequence for better throughput
        return "$sData\x00\x00\n";
      }
}

sub Deserialize {
    my $sRemain= '';
    return sub {
        $sRemain.= shift;
        if ( $sRemain=~ s/^\x00\x00(.+)\n// ) {
            my $sEscape= $1;
            return (undef, undef) if $sEscape eq 'UNDEF';
            return (undef, $sEscape);
        }
        return ('', undef) unless $sRemain=~ s/^(.*?)\x00\x00/\x00\x00/s;
        my $sData= $1;
        $sRemain=~ s/^\x00\x00\n//;
        $sData=~ s/\x01\x00/\x00/g;
        return ( $sData, undef );
    };
}

sub Escape {
    return sub {
        my $sText= shift;
        return "\0\0$sText\n";
    };
}

sub run {
    my $fSerialize   = Serialize();
    my $fDeserialize = Deserialize();
    my $fEscape      = Escape();

    print $fEscape->("[0]");

    while ( 1 ) {
        my $sLine = <>;
        last unless defined $sLine;
        my ( $sData, $sEscape )= $fDeserialize->($sLine);
        print $fSerialize->("Data: [$sData]\n") if defined $sData;
        print $fSerialize->("Escape: [$sEscape]\n") if defined $sEscape;
        print $fEscape->("[5]") if $sData;

        my $fh;
        open $fh, ">>out.txt";
        print $fh $fSerialize->("Data: [$sData]") if defined $sData;
        print $fh $fSerialize->("Escape: [$sEscape]") if defined $sEscape;
        print $fh $fEscape->("[5]") if $sData;
        close $fh; 
    }
}

1;
