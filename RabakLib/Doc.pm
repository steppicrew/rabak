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

=head1 SYNOPSIS

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
Using more than three drives probably has no benefits.

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

To make the actual backup, drop the C<-p> switch:

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

You may specify a list of devices to try more than one device and use the
first successfully mounted one. That usefull for usb-devices as backup target
when you don't know the exact device name.
  full.mount.device= /dev/sd?1 /dev/hd[cd]1

This tells B<rabak> to mount the first available (and mountable) device of
/dev/sda1, /dev/sdb1... , /dev/hdc1 and /dev/hdd1

If you specify a target group and the istarget falg, B<rabak> will make sure
that only rabak devices will be mounted (see section C<Target Groups>).

You can specify file system type and additional mount options with
  samba.mount.device= //sambaserver/share
  samba.mount.directory= /mnt/samba
  samba.mount.type= cifs
  samba.mount.opts= "username=$smb_user,password=$smb_passwd,ro"

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

Additional rsync options (like "-acl") can be specified with
  mybackup.rsync_opts = "-acl"

=head2 Target Groups

To make sure only desired devices are used to store your backup data, you
can mark a mount point as a target:
  mount1.istarget = 1

This means, that there have to be a file named I<rabak.dev.cf> (or any other
name specified by C<switch.dev_conf_file>) in the root directory of the specified
device.
If this file could not be found, this device will not be used for backup (and
even not unmounted if already mounted anywhere else).

The syntax of this file follows the one for other rabak conf files.
This config file may contain one or more targetvalues (separated by space)
in the following form:
targetvalues= <target group>[.<target value>]

You can specify a target group in your backup set by:
  mybackup.targetgroup = byweekday

In this case the device is only used if there is a target value beginning with
C<byweekday.>.
Additionally you can specify a target value at the command line (parameter
C<-i 'target value'>) to accept only devices with a matching target value.

=head3 Example for target groups and values

On one backup device your device config file contains the following line:
  targetvalues= byweekday.Mon byweekday.Wed byweekday.Fri

and another devices config file contains:
  targetvalues= byweekday.Tue byweekday.Thu byweekday.Sat

If both devices are plugged in, you set up the mount options correctly
(don't forget the C<istarget>) flag!), and you specified I<byweekday> as
targetgroup in your backup set, then you could create a daily cron job:
  rabak -i "`date "+%a"`" backup mybackup

On Mon, Wed, and Fri your files will be backed up to the first device.
On Tue, Thu and Sat the second device would be used. On Sun backup would fail.

If you don't specify a target value at the command line, the first successfully
mounted of the two devices would be used.

=head2 Notification Mails

Finally you can configure a notification mail when the free space on the target
device drops below a given value with
  full.target_discfree_threshold = 10%

valid units are 'B'yte, 'K' (default), 'M'ega, 'G'iga and '%'.
the check is performed after completing the backup job and a mail to rabak admin
is sent, if free space is below 10%.

=head1 CONFIG FILE REFERENCE

=head2 Global Switches

B<email>: mail address to send logfiles and warnings to (default: none)

B<include>: includes an other config file.

B<switch.quiet>: suppress all output and do no logging (default: I<0>)

B<switch.logging>: write log file (default: I<0>)

B<switch.verbose>: verbosity level for standard outut.
    I<-2>: only errors are printed;
    I<-1>: like I<-2> but prints warnings too;
     I<0>: like I<-1> but prints few additional information;
     I<1>: like I<0> but prints additional information;
     I<2>: more verbose (ex: prints rsync stats)
     I<3>: even more verbose (ex: prints synced files)

B<switch.pretend>: do everything but really write files to target (default: I<0>)

B<switch.dev_conf_file>: name of the device configuration file that has to exist
    on mounted target devices (path relative to device root) (default: I<rabak.dev.cf>)

B<switch.targetvalue>: specific target value that has to exist on the target
    (default: none)

=head2 Backup Set Switches

You have to specify at least B<title>, B<source>, and B<target>.

B<title>: descriptive title for backup set

B<type>: backup type. May be overridden with B<source> (default: I<file>)
    (implemented values: I<file> (default), I<mysql>, I<pgsql>)

B<source>: backup source. May start with "<type>:" specifying the bakset type.
    (see B<type>)
    for type I<file>: specify "user@host:/path" for remote sources (Target has to
    be local for remote sources!)

B<target>: backup target. May be a (local) directory or B<Target Object>.

B<mount>: B<Mount Objects> that have to be mounted before backup

B<keep>: number of old backups to keep. Superfluous versions will be deleted
    (default: unlimited)

B<filter>: (type I<file> only) list of rsync filters (seperated by whitespaces or ',').
    Literal whitespaces and ",+-&" should be escaped with backslashes ("\").
    Entries beginning with '+' are treated as includes, entires beginning with '-' are
    interpreted as excludes. If it doesn't start with '+' or '-', '+' is assumed.
    You can use parantheses to apply an include/exclude character to multiple entries.
    (Example: "-(/usr/tmp/, /var/tmp/)" is equivalent to "-/usr/temp/, -/var/tmp/")
    Paranthesis can generally be used to expand to a list of filters. (Example:
    "-/foo/(bar1 bar2)/bar3" would be expanded to "-/foo/bar1/bar3, -/foo/bar2/bar3"
    Note that there must be no space before "(" and after ")". Otherwise a new list will
    start at space. Spaces after "(" and before ")" are optional.
    (Example: "-&exclude_std" would be replaced with an exclude list containing the elements
    of config variable $exclude_std). Variable expansion is done at runtime (late expansion).
    (default: I<-&exclude +&include>)
    Effective filter rules can be displayed with 'rabak conf <bakset>'.
    B<Attention:> Pathes beginning with "/" are absolute (not relative to "source" as in
    rsync filters)
    Please specify trailing slashes for directories! Otherwise rabak will not be able to
    optimize your rules for rsync and they may not work as expected.

    A more complicated example:
        filter1= +/var/log/www/, -/var/log/
        filter2= +/etc/passwd -/etc/
        vservers= save1 save2
        filter= (&filter1 &filter2), /vservers/*/(&filter1 &filter2), +/vservers/&vservers/, -/vservers/
    Would be expanded to:
        + /var/log/www/
        - /var/log/
        + /etc/passwd
        - /etc/
        + /verservers/*/var/log/www/
        - /verservers/*/var/log/
        + /verservers/*/etc/passwd
        - /verservers/*/etc/
        + /vservers/save1/
        + /vservers/save2/
        - /verservers/
    Or more rsync'ish:
        + /
        + /var/
        + /var/log/
        + /var/log/www/
        + /var/log/www/**
        - /var/log/***
        + /etc/
        + /etc/passwd
        - /etc/***
        + /vservers/
        + /vservers/*/
        + /vservers/*/var/
        + /vservers/*/var/log/
        + /vservers/*/var/log/www/
        + /vservers/*/var/log/www/**
        - /vservers/*/var/log/***
        + /vservers/*/etc/
        + /vservers/*/etc/passwd
        - /vservers/*/etc/***
        + /vservers/save1/
        + /vservers/save1/**
        + /vservers/save2/
        + /vservers/save2/**
        - /vservers/***

B<exclude>: (type I<file> only) list of entries to be excluded. This option is
    ignored if B<filter> is set (see above).

B<include>: (type I<file> only) list of entries to be included. This option is
    ignored if B<filter> is set (see above).

B<user>: (types I<mysql> and I<pgsql> only) user to retrieve backup data as

B<password>: (types I<mysql> and I<pgsql> only) password to retrieve backup data

=head2 Mount Objects

You have to specify at least B<device> or B<directory> (if not listed in B</etc/fstab>
    both)

B<device>: one or more device(s) to mount (wildcards like C</dev/hd?1> are supported).
    If more than one device is specified, only the first successfully mounted is used.

B<directory>: directory where to mount the device to.

B<unmount>: specifies if device schould be unmounted afterwards

B<type>: filesystem type to mount (default: I<auto>)

B<opts>: additional mount options passed to mount command (default: none)
    (example: C<username=zuppi,password=zappi,ro>)

=head2 Target Object

You have at least specify B<path>.

B<path>: path of target directory

B<host>: (for remote targets only) hostname to connect to

B<port>: (for remote targets only) port to connect to (default: I<22>)

B<protocol>: (for remote targets only) ssh protocol to connect to (default: I<1,2>)
    possible values: I<1>, I<2>, I<2,1>, and I<1,2>

B<timeout>: (for remote targets only) connection timeout in seconds (default: I<150>)

B<bandwidth>: (for remote targets only) max bandwidth (default: I<0> for no limit)

B<identity_files>: (for remote targets only) identity files for ssh authentication.
    If you get 'Permission denied at RabakLib/Path.pm' try specifying id file.
    (default: empty for system settings)
    example: identity_files= /root/.ssh/id_rsa

B<user>: (for remote targets only) username to connect as

B<password>: (for remote targets only) password to authenticate
    I<Note:> not implemented yet for rsync! You have to use authentication by
        certificates

B<mount>: B<Mount Objects> to mount. Devices are considered as valid target media
    if it contains rabak device config file (see B<switch.dev_conf_file>) and
    a matching target value (if value was specified)

B<group>: target group that have to be specified on any mounted target device

B<diskfree_threshold>: if free space on target device drops below the specified
    value after completed backup, a waring mail is sent to B<email> address.
    Valid units are I<B>yte, I<K> (default), I<M>ega, I<G>iga and I<%>.


TODO: Explain the following features:

* email = rabakadmin

* full.include = /something

TODO: Explain Postgresql and MySql Backup:

* test_pg.source = pgsql:aga2,maildb

* test_pg.source = pgsql:*

* test_pg.user = *default*

* test_pg.password = test

* test_pg.keep = 7 (Keep 7, remove older)

* make a separate section for filter rules

=head2 Removing files from the backup media

!!TODO: Doc!!

Remove all occurencies of a file or directory from the backup media.

Examples:

  rabak -p rmfile /var/cache/*
  rabak rmfile /var/cache/* /tmp

=head1 RESTRICTIONS

There are still things missing:

* Send an email report

