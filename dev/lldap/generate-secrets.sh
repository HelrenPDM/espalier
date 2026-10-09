#!/usr/bin/env bash
# Writes the secrets of the development lldap container to
# dev/lldap/secrets.env (task 0007, step 28). The values exist only on the
# developer's machine. New values need `make services-down`, the removal of
# the lldap-data volume and of secrets.env, and a new `make services-up`.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f secrets.env ]; then
  exit 0
fi

umask 077
{
  printf 'LLDAP_JWT_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'LLDAP_KEY_SEED=%s\n' "$(openssl rand -hex 32)"
  printf 'LLDAP_LDAP_USER_PASS=%s\n' "$(openssl rand -hex 16)"
} > secrets.env
