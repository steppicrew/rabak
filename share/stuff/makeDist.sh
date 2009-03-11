#!/bin/bash

cd "../.."
ver=`perl -Ilib -e 'use RabakLib::Version; print VERSION;'`
vname="rabak-$ver"
basedir="../dist"

echo "Building distribution for $vname"

test -d "$basedir" || mkdir -p "$basedir"

git archive --format=tar --prefix="$vname/" HEAD | gzip > "$basedir/$vname.tar.gz"
