#!/bin/sh
# Writes DEST from the env template SRC and fills its empty secret lines
# with values read from /dev/urandom: SECRET_KEY_BASE (64 bytes) and
# CLOAK_KEY_V1 and CLOAK_HMAC_SECRET (32 bytes each) in Base64, and a
# database password, which also goes into DATABASE_URL for the service db
# of compose.yaml. It refuses to overwrite DEST. `make demo-env` and
# scripts/smoke.sh use it.
#
#   scripts/fill-secrets.sh .env.demo.example .env.demo
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 SRC DEST" >&2
  exit 2
fi

src=$1
dest=$2

if [ -e "$dest" ]; then
  echo "$dest exists; remove it first to write a new one" >&2
  exit 1
fi

random_base64() {
  head -c "$1" /dev/urandom | base64 | tr -d '\n'
}

secret_key_base=$(random_base64 64)
cloak_key=$(random_base64 32)
hmac_secret=$(random_base64 32)
# Letters and digits only, so that the password needs no escaping in the URL.
password=$(random_base64 48 | tr -d '+/=' | cut -c1-32)

umask 077
# The values reach awk through its environment, which only the same user and
# root can read, and stay out of the arguments of every command, which any
# user of the host can read in /proc while the command runs. awk joins name
# and value as strings, so no character of a value has a special meaning.
SECRET_KEY_BASE=$secret_key_base CLOAK_KEY_V1=$cloak_key CLOAK_HMAC_SECRET=$hmac_secret \
  POSTGRES_PASSWORD=$password DATABASE_URL="ecto://postgres:$password@db/espalier_prod" \
  awk '/^(SECRET_KEY_BASE|CLOAK_KEY_V1|CLOAK_HMAC_SECRET|POSTGRES_PASSWORD|DATABASE_URL)=$/ {
      name = substr($0, 1, length($0) - 1)
      print name "=" ENVIRON[name]
      next
    }
    { print }' "$src" >"$dest"
echo "Wrote $dest"
