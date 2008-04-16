#!/bin/bash

ver="$1"

vname="rabak-$ver"
basedir="../../dist/$vname"
srcdir=".."

ROOT_FILES="CHANGELOG LICENSE README TODO"
BIN_FILES="rabak faster-dupemerge"
ETC_FILES="rabak.sample.cf rabak.std.cf rabak.secret.cf"
SHARE_FILES="tutorial stuff"
MODULES="RabakLib DupMerge"

function copyFiles {
  local destdir="$1"
  local files="$2"
  
  mkdir -p "$basedir/$destdir"
  for file in $files; do
    if [ -e "$srcdir/$file" ]; then
      cp -rp "$srcdir/$file" "$basedir/$destdir/"
    fi
  done
}

function copyModule {
  local moddir="$1"
  local basedir="$2"
  local libdir="$3"
  
  mkdir -p "$basedir/$libdir/$moddir"
  for file in "$srcdir/$moddir/"*.pm; do
    cp -p "$file" "$basedir/$libdir/$moddir"
    echo 
  done
  for dir in "$srcdir/$moddir/"*; do
    if [ -d "$dir" ]; then
      bdir=`basename "$dir"`
      if [ "$bdir" = "t" ]; then continue; fi
      copyModule "$moddir/$bdir" "$basedir" "$libdir"
    fi
  done
}

function manifestModule {
  local moddir="$1"
  local subdir="$2"
  
  local pwd="`pwd`"
  cd "$moddir"
  for file in "$subdir"*; do
    if [ -e "$file" ]; then
      if [ "$file" = "." -o "$file" = ".." ]; then
        continue
      fi
      if [ -d "$file" ]; then
        manifestModule "." "$file/"
        continue
      fi
      echo "$file"
    fi
  done
  cd "$pwd"
}


if [ -z "$ver" ]; then
  echo "usage: ./makeDist.sh [version]"
  exit
fi

if [ -d "$basedir" ]; then
  echo "Directory '$basedir' already exists!"
  echo "Please delete this directory!"
  exit
fi

mkdir -p "$basedir"

for module in $MODULES; do
  copyModule $module "$basedir" "."
done

copyFiles "" "$ROOT_FILES"
copyFiles "" "$BIN_FILES"
for file in "$srcdir/"*.pl; do
  cp -p "$file" "$basedir/"
done

copyFiles "" "$ETC_FILES"

copyFiles "" "$SHARE_FILES"

  cat - > "$basedir/Makefile.PL" << EOF
use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'rabak',
    VERSION           => '$ver',
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (AUTHOR         => 'Dietrich Raisin & Stephan Hantigk <rabak@runlevel3.de>') : ()),
);
EOF
manifestModule "$basedir" > "$basedir/MANIFEST"

cd "$basedir/.."
tar -czf "$vname.tgz" "$vname"
