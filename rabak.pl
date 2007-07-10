#!/bin/bash

# wrapper for backward compatibility
scriptname="`basename "$0" ".pl"`"
dirname="`dirname "$0"`"
"$dirname/$scriptname" "$@"