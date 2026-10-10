#!/bin/sh
# Writes the license ids and the exception ids of the SPDX License List to
# priv/spdx/, where Espalier.Catalog.Pack.Spdx reads them at compile time.
# The list comes from the package spdx-license-list-data of the nixpkgs
# commit that shell.nix pins, so that an update of the pin brings the list
# of that nixpkgs.
set -eu
cd "$(dirname "$0")/.."

url=$(sed -n 's/^ *url = "\(.*\)";$/\1/p' shell.nix)
sha256=$(sed -n 's/^ *sha256 = "\(.*\)";$/\1/p' shell.nix)
pinned="import (fetchTarball { url = \"$url\"; sha256 = \"$sha256\"; }) { }"

data=$(nix-build --no-out-link -E "($pinned).spdx-license-list-data.json")
jq=$(nix-build --no-out-link -E "($pinned).jq")/bin/jq

version=$("$jq" -r .licenseListVersion "$data/json/licenses.json")
released=$("$jq" -r '.releaseDate[0:10]' "$data/json/licenses.json")

{
  echo "# SPDX License List $version ($released): license ids, deprecated ones included."
  echo "# Written by scripts/spdx-lists.sh from the nixpkgs pin of shell.nix; do not edit."
  "$jq" -r '.licenses[].licenseId' "$data/json/licenses.json" | LC_ALL=C sort
} >priv/spdx/license-ids.txt

{
  echo "# SPDX License List $version ($released): exception ids, deprecated ones included."
  echo "# Written by scripts/spdx-lists.sh from the nixpkgs pin of shell.nix; do not edit."
  "$jq" -r '.exceptions[].licenseExceptionId' "$data/json/exceptions.json" | LC_ALL=C sort
} >priv/spdx/exception-ids.txt
