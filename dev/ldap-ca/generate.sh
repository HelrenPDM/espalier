#!/usr/bin/env bash
# Creates the test CA and the server certificate of the development lldap
# (task 0007, step 28). The files stay on the developer's machine
# (.gitignore); run `make ldap-ca`, or pass --force for new ones.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f server.pem ] && [ "${1:-}" != "--force" ]; then
  echo "dev/ldap-ca/server.pem exists; pass --force to create a new CA"
  exit 0
fi

openssl req -x509 -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout ca.key -out ca.pem -days 825 -sha256 -subj "/CN=Espalier dev LDAP test CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout server.key -out server.csr -subj "/CN=localhost"
printf '%s\n' "basicConstraints=CA:FALSE" "keyUsage=critical,digitalSignature" \
  "extendedKeyUsage=serverAuth" "subjectAltName=DNS:localhost,DNS:lldap" > server.ext
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 825 -sha256 -extfile server.ext
rm -f server.csr server.ext ca.srl
# server.key is readable by the container user: a throwaway key for a local container.
chmod 600 ca.key; chmod 644 ca.pem server.pem server.key
