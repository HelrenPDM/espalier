#!/bin/sh
# Prints the number of script elements in the HTML file FILE that have no src
# attribute, so that their content would run inline, which the CSP of README
# section 6.5 blocks. Each opening tag counts on its own, also when several
# tags share a line or one tag spans lines. scripts/check-headers.sh uses it.
#
#   scripts/count-inline-scripts.sh FILE
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 FILE" >&2
  exit 2
fi

# With "<" as the record separator, each record after the first starts with
# the name of a tag; the tag ends at the first ">".
awk '
  BEGIN { RS = "<"; count = 0 }
  NR > 1 && tolower($0) ~ /^script([[:space:]>\/]|$)/ {
    tag = $0
    end = index(tag, ">")
    if (end > 0) tag = substr(tag, 1, end - 1)
    if (tolower(tag) !~ /[[:space:]]src[[:space:]]*=/) count++
  }
  END { print count }
' "$1"
