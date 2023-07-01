#!/usr/bin/env bash

[ -z "$3" ] && { echo "Usage: $0 host port request_file"; exit 1; }

nc "$1" "$2" < $3