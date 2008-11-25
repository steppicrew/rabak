#!/bin/bash

# This script calls rabak inside it's archive's directory

basedir=`dirname "$0"`

perl -I "${basedir}/lib/" "${basedir}/rabak" "$@"
