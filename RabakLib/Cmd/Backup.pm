#!/usr/bin/perl;

package RabakLib::Cmd::Backup;

use warnings;
use strict;

use Data::Dumper;

use vars qw(@ISA);

@ISA= qw( RabakLib::Cmd );

# sub new {
#     my $class= shift;
# 
#     my $self= $class->SUPER::new();
#     bless $self, $class;
# }

# print "BACKUP!!\n";

sub GetOptions {
    return {
        "targetgroup-value" =>  [ "",  "s", "<value>",   "Save on device with targetgroup value <value>" ],
        "ha" =>                 [ "",  "",  "",          "HA" ],
    };
}

sub run {
    my $self= shift;

    return if $self->want_args(0, 1);

#    print Dumper($hOpts);
#    print Dumper($hArgs);

    return 1;
}

1;
