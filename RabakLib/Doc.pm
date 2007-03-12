#!/usr/bin/perl

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

# You can run this file through either pod2man or pod2html to produce pretty
# documentation in manual or html file format (these utilities are part of the
# Perl 5 distribution).

# Copyright 2006 Dietrich Raisin.  All rights reserved.
# It may be used and modified freely, but I do request that this copyright
# notice remain attached to the file.  You may modify this module as you
# wish, but if you redistribute a modified version, please attach a note
# listing the modifications you have made.

# The most recent version and complete docs are available at:
#   http://www.raisin.de/rabak

# ---- developer notes ----

# TODO:
# syslog vs baklog
# $ in config

# test:-1a
# test:0 == test
# test:09-04
# test:2006-09:2006-10-04

# exitcodes:
# 1 usage, help
# 2 wrong parameter
# 3 error in conf file
# 9 other error

# -------------------------

__END__

=head1 NAME

rabak - A reliable rsync based backup system, simple to configure, simple to run, simple to restore data

=head1 SYSNOPSIS

C<rabak backup myserver>

C<rabak conf>

C<rabak conf myserver>

=head1 DESCRIPTION

=head2 Jay! Another backup solution!

If the data you have to back up is not more then 200 GB and daily changes are not more than 1 GB, then
B<rabak> may be a simple, reliable and inexpensive solution for you.

Most backup systems are based on the assumption that the space available on a backup media is smaller than
the space of the data to be backed up. This is like is has been for a very long time and many people
still are setting up backup systems based on this assumption. And they have to change the backup
medias every day, hoping that the data can be restored when needed.

How about using an external 500 GB hard drive as backup media?
The data that most offices work with is often much less than 500 GB.
And such a drive costs nothing compared with professional streamer hardware (plus media).

=head2 How it works

B<rabak> is based on rsync's hardlinking abilities. It I<always> makes a full backup. You'll get a
directory containing the complete tree with each backup. But an unchanged file from one backup is
hardlinked to the file from the last backup. So it doesn't consume any disk space. 

Full backups? Won't the backup drive be full very quickly? No! Here's an example:
You have a 500 GB drive (backup), 100 GB of data with 500 MB changes/day. So your drive
will fill up in (500 - 100) / 0.5 days. That's 800 days, or 2 1/2 years! When it's full,
you but in in the cellar in a nice and dry place, and buy the next drive. That will
be a 2 TB drive, probably :-) .

What if the hard drive breaks? Then your data will be gone.
That's why you will need at least two drives. You still want redundancy.
Swap drives every week and put one in a place safe from fire or theft.
Using three drives is highly recommended.
Things may awfully go wrong once in 2 1/2 years.
Using more than three drives has no benefits.

=head2 Features

* Very simple to restore data. Just look for the file on the backup drive and copy it back.

* Simple perl script. The script is very easy to understand and to extend.

* TODO

=head2 Tips

* If the backup drive is full and you haven't got a replacement at hand, you can delete any
old backup directory (even the first one).
All hardlinked files are equal, there's no "primary file" or such, so it doesn't matter
which one you remove.
You could keep the first one and remove every second of the very old backup directories.
Or keep every Monday backup and remove the others.

* If your backup target is a mounted device, then set your target to a subdirectory and not
to the root of the device. In this way, if a mount fails, the writing of files fails too.
So no files are written to your (unmounted) mount point.

=head2 Drawbacks

* Workstations can't be backed up directly. This is how to do it: Install a hard drive into the
server and copy the workstation data on that. Then configure B<rabak> to backup this hard drive.
That works fine.

=head2 Configuration

The configuration file syntax is quite similar to postfix'.
It's important to make it read- and writable only to the user who calls the script. Parts of the
configuration may be fed to system calls, which run with the user's rights.

You define I<backup sets>, each must
have a title, a source and a target. As a default, B<rabak> looks for I<rabak.cf> as its configuration
file, which may look like this:

  mybackup.title = My home directory
  mybackup.source = /home/me
  mybackup.target = /mnt/sda1
  mybackup.switch.logging = 1

Check the configuration:

  rabak conf mybackup

The following command will I<pretend> to make a backup of C</> in C</mnt/sda1/2006-09.test/2006-09-24.test>
(these are example dates, of cause)
and write a log file to C</mnt/sda1/2006-09-log/2006-09-24.test.log>:

  rabak -p backup mybackup

To make the actual backup, leave away the C<-p> switch:

  rabak backup mybackup

You can have multiple backup sets in your your configuration file and use variables:

  my_target = /mnt/sda1/bak

  myhome.title = My home directory
  myhome.source = /home/me
  myhome.target = $my_target
  myhome.switch.logging = 1

  full.title = Full server backup
  full.source = /
  full.target = $my_target
  full.switch.logging = 1

Setting C<switch.logging> overrides the command line option C<-l>.
Possible C<switch>es are C<pretend>, C<quiet> and C<logging>.
C<$my_target> is replaced by C</mnt/sda1>.
Now lets add a mount point:

  full.mount.device= /dev/sda1
  full.mount.directory= /mnt/sda1
  full.mount.unmount= 1

This tells B<rabak> to mount C</dev/sda1> before starting backing up C<full>, and
to unmount when done.

Probably you want to use the same mount point for several backup sets. So you can
use a variable to define it. Replace the last addition by this code:

  mount1.device= /dev/sda1
  mount1.directory= /mnt/sda1
  mount1.unmount= 1

  ..

  full.mount = $mount1

To exclude files from being backed up, add this:

  full.exclude = /dev
        /proc
        tmp/
        *.bak

See the rsync man page (EXCLUDE PATTERN RULES) for details.
You can use variables to define exclude sets and glue them together:

  exclude_common =
        /dev
        /proc

  exclude_fileserver = *.bak

  full.exclude = $exclude_common $exclude_fileserver

To make sure you use the right backup device you can define a target group:
  mybackup.targetgroup = mytargetgroup

If you specify a mount point with
  mount1.istarget = 1

then - after mounting - there has to be a file named C<mytargetgroup.ids> in the
target directory. If not, the device is unmounted and the next one is tried (if it
was one of I<firstof>).

Additionally you can put target ids in this file - one per line - and specify
an id at the command line with switch "-i". The backup will be done on the device
containing the id in the target group file.

Example:
On one disk there is a file I<bak/mytargetgroup.ids> with
  Mon
  Wed
  Fri

and on another disk the same file contains
  Tue
  Thu
  Sat

Now you can have both disks plugged in and with
  raback -i "`date "+%a"`" backup mybackup

the 1st disk will be used on Mon, Wed and Fri
an the 2nd disk will be used on Tue, Thu and Sat.
On Sunday ther will be an error.


TODO: Explain the following features:

* email = rabakadmin

* full.include = /something

* full.mount= firstof mount1 mount2 mount3 ; mount_boot

TODO: Explain Postgresql and MySql Backup:

* test_pg.source = pgsql:aga2,maildb

* test_pg.source = pgsql:*

* test_pg.user = *default*

* test_pg.password = test

* test_pg.keep = 7 (Keep 7, remove older)

=head2 Removing files from the backup media

!!TODO: Doc!!

Remove all occurencies of a file or directory from the backup media.

Examples:

  rabak -p rmfile /var/cache/*
  rabak rmfile /var/cache/* /tmp

=head1 RESTRICTIONS

There are still things missing:

* Send an email report

