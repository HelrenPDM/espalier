#!/bin/sh
# Searches the tracked files for the terms of the maintainer's deny-list of
# organization and project names. DENYLIST_FILE names the list, one term per
# line. The list itself never enters the repository (README section 13).
set -eu

if [ -z "${DENYLIST_FILE:-}" ]; then
  echo "DENYLIST_FILE is unset; the deny-list check is skipped."
  exit 0
fi

if [ ! -r "$DENYLIST_FILE" ]; then
  echo "Cannot read the deny-list $DENYLIST_FILE." >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"

# An empty pattern matches every line, so blank lines and carriage returns of
# the list are dropped before git grep reads the terms from standard input.
status=0
matches=$(tr -d '\r' <"$DENYLIST_FILE" | grep -v '^[[:space:]]*$' |
  git grep -i -l -F -f -) || status=$?

case $status in
  0)
    echo "Deny-listed terms found in these tracked files:" >&2
    printf '%s\n' "$matches" >&2
    exit 1
    ;;
  1)
    echo "No deny-listed term found in the tracked files."
    exit 0
    ;;
  *)
    echo "git grep failed with exit code $status." >&2
    exit "$status"
    ;;
esac
