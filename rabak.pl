#!/bin/bash

# wrapper for backward compatibility
scriptname="`basename "$0" ".pl"`"
dirname="`dirname "$0"`"

echo "WARNING: please use '$dirname/$scriptname'!"
echo "calling $0 is deprecated!"

"$dirname/$scriptname" "$@"