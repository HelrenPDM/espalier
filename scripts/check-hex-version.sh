#!/bin/sh
# Stops the quality gate before `mix hex.audit` when Hex is older than 2.5.1.
# An older Hex neither reports advisories in `mix hex.audit` nor reads
# `ignore_advisories` from mix.exs (README section 13).
set -eu

required=2.5.1
version=$(mix hex.info | sed -n 's/^Hex: *//p')

# An empty version counts as too old.
if [ -n "$version" ] &&
  [ "$(printf '%s\n%s\n' "$required" "$version" | sort -V | head -n 1)" = "$required" ]; then
  echo "Hex $version"
  exit 0
fi

echo "Hex $version is older than $required. Run mix local.hex --force." >&2
exit 1
