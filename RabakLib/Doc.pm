#!/usr/bin/perl

# You can run this file through either pod2man or pod2html to produce pretty
# documentation in manual or html file format (these utilities are part of the
# Perl 5 distribution).

# The most recent version and complete docs are available at:
#   http://www.raisin.de/rabak

# ---- developer notes ----

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

=head2 A clever backup solution!

If the data you have to back up is not more then 200 GB and daily changes are not more than 1 GB, then
B<rabak> may be a simple, reliable and inexpensive solution for you.

Most backup systems are based on the assumption that the space available on a backup media is smaller than
the space of the data to be backed up.
This is like is has been for a very long time and many people still are setting up backup systems
based on this assumption.
And they have to change the backup medias every day, hoping that the data can be restored when needed.

How about using an external 500 GB hard drive as backup media?
The data that offices work with is often much less than 500 GB.
And such a drive costs nothing compared with professional streamer hardware (plus media).

=head2 How it works

B<rabak> is based on rsync's hardlinking abilities.
It I<always> makes a full backup.
You'll get a directory containing the complete tree with each backup.
But an unchanged file from one backup is hardlinked to the file from the last backup.
So it doesn't consume any additional disk space.

Full backups? Won't the backup drive be full very quickly?
No! Here's an example:
You have a 500 GB drive (backup), 100 GB of data with 500 MB changes/day.
So your drive will fill up in (500 - 100) / 0.5 days.
That's 800 days, or 2 1/2 years!
When it's full, you put it in the cellar in a nice and dry place, and buy the next drive.
That will be a 2 TB drive then, probably :-) .

What if the hard drive breaks? Then your data will be gone.
That's why you will need at least two drives. You still want redundancy.
Swap drives every week and put one in a place safe from fire or theft.

Using three drives is highly recommended.
Things may awfully go wrong once in 2 1/2 years.
Using more than three drives probably has no benefits.

=head2 Features

=over 2

=item *

Each source or target may be local or remote

=item *

Unique support of backup from one remote machine to another. It's like using a remote control!

=item *

Very simple to restore data. Just look for the file on the backup drive and copy it back.

=item *

Simple perl script. The script is very easy to understand and to extend.

=item *

TODO

=back

=head2 Tips

=over 2

=item *

If the backup drive is full and you haven't got a replacement at hand, you can delete any
old backup directory (even the first one).
All hardlinked files are equal, there's no "primary file" or such, so it doesn't matter
which one you remove.
You could keep the first one and remove every second of the very old backup directories.
Or keep every Monday backup and remove the others.

=item *

If your backup target is a mounted device, then you have to create a file named "rabak.dev.cf"
in the root directory of that device. This prevents copying data to wrong devices.
(L<Targets>)

=item *

To back up workstations you only have to install rsync and a ssh daemon on the workstatsion.
(L<Remote Targets and Sources>)

=back

=head2 Configuration

It's important to make it read- and writable only to the user who calls the script.
Parts of the configuration may be fed to system calls, which run with the user's rights.

The configuration file syntax is based on postfix' configuration syntax.

You can define variables and objects, containing variables or other objects
separated by C<.> (see section L<CONFIG FILE REFERENCE>).

Example:

    value = some value
    object1.prop = some other value
    object1.prop2 = another value
    object1.subobject.prop1 = subobject's value
    object2.something_other = object2's value

This would set C<value> to C<some value>, create an object C<object1> with
porperties C<prop>, C<prop2> and object C<subobject> and a 2nd object
C<object2>.

Properties of objects can be grouped in ini file style:

Example from above in ini style:

  []
  value = some value
  [object1]
  prop = some other value
  prop2 = another value
  subobject.prop1 = subobject's value
  []
  object2.something_other = object2's value

The line C<[]> resets the object's prefix to nothing.
Identifiers in C<[...]> are simply prepended to following identifiers, so
you can have multiple ini sections with the same name.

You define I<backup sets>, each must have a title, one or more sources and a target.
As a default, B<rabak> looks for F<rabak.cf> as its configuration file, which may look like this:

  [mybackup]
  title = My home directory
  source = /home/me
  target = /mnt/sda1/rabak
  switch.logging = 1

To check the configuration:

  rabak conf mybackup

The following command will I<pretend> to make a backup of F</home/me> in
F</mnt/sda1/rabak/2006-09.test/2006-09-24.test> (these are example dates, of course)
and write a log file to F</mnt/sda1/rabak/2006-09-log/2006-09-24.test.log>:

  rabak -p backup mybackup

To make the actual backup, drop the C<-p> switch:

  rabak backup mybackup

You can have multiple backup sets in your configuration file and use variables:

  []
  my_target = /mnt/sda1/rabak

  [myhome]
  title = My home directory
  source = /home/me
  target = $my_target
  switch.logging = 1

  [full]
  title = Full server backup
  source = /
  target = $my_target
  switch.logging = 1

Setting C<switch.logging> overrides the command line option C<-l>.
Possible C<switch>es are C<pretend> and C<logging>.
C<$my_target> is replaced by C</mnt/sda1/rabak>.

Now lets add a mount point:

  [full]
  mount.device= /dev/sda1
  mount.directory= /mnt/sda1
  mount.unmount= 1

This tells B<rabak> to mount F</dev/sda1> before starting backing up C<full>, and
to unmount it when done (true by default, set it to "0" to suppress unmounting).

You may specify a list of devices to try more than one device and use the first successfully
mounted one.
That's useful for usb-devices as backup targets when you don't know the exact device name.

  [full]
  mount.device= /dev/sd?1 /dev/hd[cd]1

This tells B<rabak> to mount the first available (and mountable) device of
F</dev/sda1>, F</dev/sdb1>..., F</dev/hdc1>, and F</dev/hdd1>

If you specify a target group, B<rabak> will make sure that only rabak devices
will be mounted (see section L<Target Groups>).

You can specify file system type and additional mount options with

  [samba.mount]
  device= //sambaserver/share
  directory= /mnt/samba
  type= cifs
  opts= "username=$smb_user,password=$smb_passwd,ro"

Probably you want to use the same mount point for several backup sets.
So you can use a variable to define it.
Replace the last addition by this code:

  [mount1]
  device= /dev/sda1
  directory= /mnt/sda1
  unmount= 1
  []
  ..
  full.mount = &mount1

To exclude files from being backed up, add this:

  []
  full.exclude = /dev
        /proc
        tmp/
        *.bak

See L<filter> and L<rsync/EXCLUDE PATTERN RULES> for details.
You can use variables to define exclude sets and glue them together:

  []
  exclude_common =
        /dev
        /proc

  exclude_fileserver = *.bak

  full.exclude = $exclude_common $exclude_fileserver

Additional rsync options (like "-acl") can be specified with

  mybackup.rsync_opts = "-acl"

=head2 Targets

If you want to mount backup devices, you can define a "L<Target Object|Target Objects>".

  [mount1]
  device= /dev/sd?1
  directory= /mnt/backup
  []
  ...
  [mytarget]
  path= /mnt/backup/rabak/
  mount= $mount1
  []
  ...
  full.target= &mytarget

This would mount the device specified in I<$mount1> to back up your data.

To make sure only desired devices are used to store your backup data,
devices mounted in a "L<Target Object|Target Objects>" have to be a file named F<rabak.dev.cf>
(or any other name specified by switch.dev_conf_file) in the root directory.
If this file could not be found, this device will not be used for backup (and
even not unmounted if already mounted anywhere else).
If you specified multiple devices (like in our example) the next device is tried.

The syntax of F<rabak.dev.cf> follows the one for other rabak conf files.
This config file may contain one or more target values (separated by space)
in the following form:

  targetvalues= <target group>[.<target value>]

You can specify a target group in your backup set by:

  mytarget.group = byweekday

In this case the device is only used if there is a target value beginning
with C<byweekday.>.
Additionally you can specify a target value at the command line (parameter C<-i 'target value'>)
to accept only devices with a matching target value.

Example for target groups and values

On one backup device your device config file contains the following line:

  targetvalues= byweekday.Mon byweekday.Wed byweekday.Fri

and another device's config file contains:

  targetvalues= byweekday.Tue byweekday.Thu byweekday.Sat

If both devices are plugged in, you set up the mount options correctly, and you
specified C<byweekday> as target group in your L<Target Object|Target Objects>, then you could create
a daily cron job:

  rabak -i "`date "+%a"`" backup mybackup

On Mon, Wed, and Fri your files will be backed up to the first device.
On Tue, Thu and Sat the second device would be used. On Sun backup would fail.

If you don't specify a target value at the command line, the first successfully
mounted of the two devices would be used.

=head2 Remote Targets and Sources

To back up your data to or from remote hosts, you simply have to specify a host name and
an optional user name in your L<Source|Source Objects>/L<Target Object|Target Objects> (for full syntax see
L</"CONFIG FILE REFERENCE"> and L</"Path Objects">):

  [mytarget]
  host= rabak.localdomain
  user= rabak

B<rabak> will connect to the remote machine via ssh and mount any needed device there,
before backing up your data.

You may even specify remote sources B<and> target at the same time to back up your
data from one host to another. 

B<Note>: You have have to set up key authentication for ssh to login to the remote hosts.
For remote to remote backups make sure that both hosts can connect each other as well. 

=head2 Notification Mails

Configure a notification mail when the free space on the target
device drops below a given value:

  [mytarget]
  discfree_threshold = 10%

The check is performed after completing the backup job and a mail to B<rabak> admin
is sent, if free space is below 10%.

Valid units are 'B'yte, 'K' (default), 'M'ega, 'G'iga and '%'.

=head1 CONFIG FILE REFERENCE

=head2 Introduction

Lines beginning with C<#> are treated as comments.
Lines beginning with whitespaces are treated as continuation of the previous line.

You can define variables and objects. Variables are simple strings, objects
contain other objects and/or variables.
object's properties are addressed with points (C<.>).

Example:
  exclude= /tmp/
    /home/*/temp/
  include= /home/
  bakset1.title= My Bakset Title
  bakset1.name= My Bakset Name
  bakset1.type= file 
  bakset1.mount.path= /mnt/backup 

You may group settings for the same object in ini file sytle:
  [bakset1]
  title= My Bakset Title
  name= My Bakset Name
  type= file 
  mount.path= /mnt/backup 

This defines the same C<bakset1> object as above. With C<[]> you can reset
to the root namespace.

Referring to other values or objects is done by prefix C<$> or C<&>.
References prefixed by C<$> are replaced literally during the parsing process
of the config file. Therefore the referenced object/value has to be defined
before the reference.
Example:
  exclude= -/tmp/
  filter= $exclude
  exclude= -/var/

would expand C<filter> to C<-/tmp/>.

References prefixed by C<&> are handled at runtime.
Example:
  exclude= -/tmp/
  filter= &exclude
  exclude= -/var/

would expand C<filter> to C<-/var/>.

Generally C<&> has to be used where references to multiple objects are required
(like L<mount> and L<source>) or where values should be handled in a special way
(L<filter>).

For details on object expansion see L<mount>, L<source>, L<target> and L<filter>.

Currently the following object types are known:
L<Bak Set Objects>, L<Mount Objects>, L<Source Objects>,
and L<Target Objects>

=head2 Global Values

=over 2

=item email

mail address to send logfiles and warnings to (default: none)

=item INCLUDE

includes an other config file.

=item END

ends config file. Any text following this line is ignored.

=item switch.logging

log level. 0= none, 1= errors, 2= warnings, 3= info, 4= debug (default: C<2>)

=item switch.pretend

do everything but don't really write files to target (default: C<0>)

=item switch.dev_conf_file

name of the device configuration file that has to exist
on mounted target devices (path relative to device root) (default: F<rabak.dev.cf>)

=item switch.targetvalue

specific target value that has to exist on the target
(default: none)

=back

=head2 Backup Set Values

You have to specify all values B<title>, B<name>, B<source>, and B<target>.

=over 2

=item title

descriptive title for backup set

=item name

name of backup set. Will be used to name the target directory.

=item source

backup source. May be a (local) directory or a L<Source Object|Source Objects>.
You can specify more than one source by path or reference to a L<Source Object|Source Objects>.
All those sources will be backed up to your target.
References to L<Source Objects> have to be preceeded by C<&>.

=item target

backup target. May be a (local) directory or a L<Target Object|Target Objects> (preceeded by C<&>).

=back

=head2 Mount Objects

You have to specify at least B<device> or B<directory>. Both if neither is listed in B</etc/fstab>.

=over 2

=item device

one or more device(s) to mount (wildcards like C</dev/hd?1> are supported).
If more than one device is specified, only the first successfully mounted is used.

=item directory

directory where to mount the device to.

=item unmount

specifies if device should be unmounted afterwards

=item type

filesystem type to mount (default: I<auto>)

=item opts

additional mount options passed to mount command (default: none)
(example: C<username=zuppi,password=zappi,ro>)

=back

=head2 Path Objects

Path Objects specify sources or targets for backups. At least you have to specify a path value.

Common values for L<Target|Target Objects> and L<Source Objects|Source Objects> are:

=over 2

=item path

Path of source/target directory (See L<Source Objects> for further information).

=item host (for remote paths only)

Hostname to connect to.

=item port (for remote paths only) 

Port to connect to (default: C<22>).

=item protocol (for remote paths only) 

SSH protocol to connect to (default: C<2>).
Possible values: I<1>, I<2>

=item timeout (for remote paths only) 

Connection timeout in seconds (default: C<150>).

=item user (for remote paths only)

Username to connect as.

=item mount

L<Mount Objects> to mount. See L<Target Objects> for further information
on mounts at target.

=back

=head3 Source Objects

=over 2

=item name

Name of source. This value is used to name the backup directory on the target.
If not set, a name will be built from path. 

=item type

Backup type. May be overwritten with L<path> (default: C<file>)
(implemented values: I<file> (default), I<mysql>, I<pgsql>)

=item path

Backup source. May start with "<type>:" specifying the bakset type. (see L<type>)

For types I<mysql> and I<pgsql>: Path can be C<*> for all databases or comma separated
list with database names. (Example: C<path=mysql:*> or C<path=pgsql:template1,template2>)

=item keep

Number of old backups to keep. Superfluous versions will be deleted
(default: C<0>, meaning unlimited)

=item filter (type I<file> only)

List of rsync like filters (seperated by whitespaces or C<,>).

Rsync filters tend to be rather wierd and B<rakab> does some magick(TM) to make a
hard administators life easier.
This option is an I<alternative> to the L<include> and L<exclude>
options and lets you describe more complex rules (without feeling more complex).

Filters are applied from top to bottom.
Filter checking is canceled at the first matching filter entry.
You don't have to care about rsync's special filter behavior.

Entries for directories will match the directory and all contained files.
(Note: Please use trailing slashes for directories for those optimizations!)

Literal whitespaces and C<,+-&> should be escaped with backslashes (C<\>).
Entries beginning with C<+> are treated as includes, entries beginning with C<-> are
interpreted as excludes.
If it doesn't start with C<+> or C<-> or if the sign is ambiguous, this
rules is ignored and a warning is raised.

You can use parantheses to apply an include/exclude character to multiple entries.
(Example:C<-(/usr/tmp/, /var/tmp/)> is equivalent to C<-/usr/temp/, -/var/tmp/>)

Paranthesis can generally be used to expand to a list of filters.
(Example: C<-/foo/(bar1 bar2)/bar3> would be expanded to C<-/foo/bar1/bar3, -/foo/bar2/bar3>)

Note that there must be I<no> space before C<(> and after C<)>. Otherwise a new list will
start at space. Spaces after C<(> and before C<)> are optional.
(Example: C<-&exclude_std> would be replaced with an exclude list containing the elements
of config variable $exclude_std.)

Variable expansion is done at runtime (late expansion).
(default: C<-&exclude +&include>)

Effective filter rules can be displayed with C<rabak -v conf E<lt>baksetE<gt>>.
B<Attention:> Pathes beginning with C</> are absolute (not relative to C<source> as in
rsync filters)

You have to add trailing slashes for directories! Otherwise rabak will not be able to
optimize your rules for rsync and they may not work as expected.

A more complicated example:
Let's assume you want to include everything under F</var/log/www/> but nothing else from F</var/log/>.
Additionally you want to save nothing except file F<passwd> from F</etc/>.
These rules should apply to your root directory and to your vservers
- but you only want to back up vservers C<save1> and C<save2>.

To do so, you could set your rules as follows:

  filter1= +/var/log/www/, -/var/log/
  filter2= +/etc/passwd -/etc/
  vservers= save1 save2
  filter=
    &filter1 &filter2,
    /vservers/*/(&filter1 &filter2),
    +/vservers/&vservers/,
    -/vservers/

Would be expanded to:

  + /var/log/www/
  - /var/log/
  + /etc/passwd
  - /etc/
  + /vservers/*/var/log/www/
  - /vservers/*/var/log/
  + /vservers/*/etc/passwd
  - /vservers/*/etc/
  + /vservers/save1/
  + /vservers/save2/
  - /vservers/

And would then feed rsync with:

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

=item exclude (type I<file> only)

List of entries to be excluded. This option is ignored if L</filter> is set (see above).

=item include (type I<file> only)

List of entries to be included. This option is ignored if L</filter> is set (see above).

=item scan_bak_dirs (type I<file> only)

Number of last backups to consider for hard links (default: C<4>).

=item dbuser (types I<mysql> and I<pgsql> only)

User to connect database as.

=item dbpassword (types I<mysql> and I<pgsql> only).

Password to connect to database

=item packer (types I<mysql> and I<pgsql> only)

Program for packing dumps. valid values are C<bzip2> and C<gzip> (default: C<bzip2>).

=back

=head3 Target Objects

=over 2

=item mount

Devices are considered as valid target media if it contains rabak device config
file (see L<switch.dev_conf_file>) and a matching target value (if value was specified)

=item bandwidth (for remote targets only)

Max bandwidth (default: C<0> for no limit).

=item identity_files (for remote targets only)

Identity files for ssh authentication.
If you get C<Permission denied at RabakLib/Path.pm> try specifying B<identity_files>.
(Default: empty for system settings.)
Example: C<identity_files= /root/.ssh/id_rsa>

=item group

Target group that have to be specified on any mounted target device.

=item diskfree_threshold

If free space on target device drops below the specified
value after completed backup, a warning mail is sent to B<email> address.
Valid units are I<B>yte, I<K> (default), I<M>ega, I<G>iga and I<%>.

=back

TODO: Explain the following features:

=over 2

=item *

email = rabakadmin

=item *

explain bug in rsync-2.6.8 (--dry-run raises errors in combination with --link-dest)

=back

=head2 Removing files from the backup media

!!Currently not implemented!!

=head1 BUGS AND LIMITATIONS

Not many. Can't make coffee.

=head1 AUTHOR

Written by Stephan Hantigk <steppi@steppicrew.de> and Dietrich Raisin <info1@raisin.de>!

LICENSE

Copyrights 2007-2008 by Stephan Hantigk & Dietrich Raisin. For other contributors see CHANGELOG.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
See http://www.perl.com/perl/misc/Artistic.html
