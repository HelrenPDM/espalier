#!/bin/sh
# Checks the security headers and cookies of README section 6.5 on a running
# instance and fails on any mismatch (task 0017, step 5).
#
#   scripts/check-headers.sh BASE_URL
#
# BASE_URL is http://localhost:<port> for the application container, or the
# https origin of the reverse proxy. The script checks the proxy header HSTS
# only for an https BASE_URL.
#
# Environment:
#   PUBLIC_URL           the origin that every POST sends in Origin, as the
#                        CSRF layers of README section 6.5 require (default
#                        BASE_URL)
#   CHECK_CA_FILE        a CA certificate for curl --cacert, such as the local
#                        root certificate of Caddy
#   CHECK_CONTAINER      the application container; the script then reads the
#                        options of the transaction cookie with bin/espalier eval
#   CHECK_OIDC_PROVIDER  the key of a configured OIDC provider; the script then
#                        checks the Set-Cookie header of GET /auth/oidc/<key>
#
# curl 8.5.0 stores a __Host- cookie received from http://localhost in its
# cookie jar. The script reads the Set-Cookie header and sends the Cookie
# header itself, which works with any curl version.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 BASE_URL" >&2
  exit 2
fi

base=${1%/}
origin=${PUBLIC_URL:-$base}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

csp="default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
trusted_types="require-trusted-types-for 'script'"
permissions="camera=(), microphone=(), geolocation=(), payment=(), usb=(), publickey-credentials-create=(self), publickey-credentials-get=(self)"
hsts="max-age=63072000; includeSubDomains"

ok() { echo "ok    $1"; }

fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

expect() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1: got '$2', want '$3'"; fi
}

# fetch HEADERS BODY CURL_ARGS...: writes the headers and the body of one
# request to the two files and prints the status code.
fetch() {
  headers=$1
  body=$2
  shift 2

  if [ -n "${CHECK_CA_FILE:-}" ]; then
    curl -sS --max-time 20 --cacert "$CHECK_CA_FILE" -D "$headers" -o "$body" -w '%{http_code}' "$@"
  else
    curl -sS --max-time 20 -D "$headers" -o "$body" -w '%{http_code}' "$@"
  fi
}

# values FILE NAME: prints the value of every header NAME in FILE, one per
# line, without the line ends of HTTP.
values() {
  tr -d '\r' <"$1" | awk -v name="$2" '
    BEGIN { name = tolower(name) }
    {
      i = index($0, ":")
      if (i > 0 && tolower(substr($0, 1, i - 1)) == name) {
        v = substr($0, i + 1)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        print v
      }
    }'
}

# cookie FILE NAME: prints the Set-Cookie line of the cookie NAME.
cookie_line() {
  values "$1" set-cookie | grep "^$2=" | head -n 1 || true
}

# check_cookie LABEL LINE SAMESITE [MAX_AGE]: the attributes of README
# section 6.5, a __Host- name, and no Domain.
check_cookie() {
  label=$1
  line=$2

  if [ -z "$line" ]; then
    fail "$label: no Set-Cookie header"
    return
  fi

  attributes=$(printf '%s\n' "$line" | cut -d';' -f2- | tr ';' '\n' | sed 's/^ *//; s/ *$//' | tr '[:upper:]' '[:lower:]')

  for attribute in secure httponly "path=/" "samesite=$3" ${4:+"max-age=$4"}; do
    if printf '%s\n' "$attributes" | grep -qx "$attribute"; then
      ok "$label: $attribute"
    else
      fail "$label: attribute $attribute is missing in '$line'"
    fi
  done

  if printf '%s\n' "$attributes" | grep -q '^domain='; then
    fail "$label: carries a Domain attribute"
  else
    ok "$label: no Domain"
  fi

  case $line in
    __Host-*) ok "$label: __Host- prefix" ;;
    *) fail "$label: name without the __Host- prefix" ;;
  esac
}

# Fixed headers of every response, the Vary list and, behind the proxy, HSTS.
for path in / /api/session /health; do
  fetch "$work/h" "$work/b" "$base$path" >/dev/null
  label="GET $path"
  expect "$label: content-security-policy" "$(values "$work/h" content-security-policy)" "$csp"
  expect "$label: content-security-policy-report-only" "$(values "$work/h" content-security-policy-report-only)" "$trusted_types"
  expect "$label: cross-origin-opener-policy" "$(values "$work/h" cross-origin-opener-policy)" "same-origin"
  expect "$label: cross-origin-resource-policy" "$(values "$work/h" cross-origin-resource-policy)" "same-origin"
  expect "$label: referrer-policy" "$(values "$work/h" referrer-policy)" "strict-origin-when-cross-origin"
  expect "$label: x-content-type-options" "$(values "$work/h" x-content-type-options)" "nosniff"
  expect "$label: permissions-policy" "$(values "$work/h" permissions-policy)" "$permissions"

  # Bandit adds its own Vary line for compression; the field values form one
  # list (RFC 9110, section 5.3).
  vary=$(values "$work/h" vary | tr '\n' ',' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  for token in sec-fetch-site sec-fetch-mode sec-fetch-dest; do
    case ",$vary," in
      *",$token,"*) ok "$label: vary $token" ;;
      *) fail "$label: vary lacks $token in '$vary'" ;;
    esac
  done

  case $base in
    https://*)
      expect "$label: strict-transport-security" "$(values "$work/h" strict-transport-security)" "$hsts"
      ;;
  esac
done

# The session cookie and the CSRF token of GET /api/session.
fetch "$work/session-h" "$work/session-b" "$base/api/session" >/dev/null
session_cookie=$(cookie_line "$work/session-h" __Host-espalier)
check_cookie "__Host-espalier" "$session_cookie" strict
cookie=${session_cookie%%;*}
csrf=$(sed -n 's/.*"csrf_token":"\([^"]*\)".*/\1/p' "$work/session-b")

if [ -z "$csrf" ]; then
  fail "GET /api/session: no csrf_token"
fi

# post PATH JSON: a POST with Origin, the CSRF token and the session cookie;
# prints the status code.
post() {
  fetch "$work/h" "$work/b" -X POST -H "Origin: $origin" -H "x-csrf-token: $csrf" \
    -H "Cookie: $cookie" -H "content-type: application/json" --data "$2" "$base$1"
}

# Cache-Control: no-store on the personal routes of tasks 0004, 0013 and
# 0015; the answers without a session or role count as well.
for path in /api/session /api/me/progress /api/admin/users /api/registrar/credentials /api/policies; do
  fetch "$work/h" "$work/b" "$base$path" >/dev/null
  expect "GET $path: cache-control" "$(values "$work/h" cache-control)" "no-store"
done

for request in "/api/auth/demo {\"slot\":0}" "/api/facilitator/user-lookups {}" "/api/integration/credential-lookups {}"; do
  path=${request%% *}
  status=$(post "$path" "${request#* }")
  expect "POST $path: cache-control" "$(values "$work/h" cache-control)" "no-store"

  # The CSRF layers accept the request; its answer is about the body or the
  # missing session.
  if [ "$path" = /api/auth/demo ]; then
    case $status in
      403) fail "POST $path: 403, the CSRF layers refused Origin, token or cookie: $(cat "$work/b")" ;;
      *) ok "POST $path: passes the CSRF layers ($status)" ;;
    esac
  fi
done

# Content types that match the body, with charset=utf-8 for every text type
# (ASVS 4.1.1).
fetch "$work/index-h" "$work/index.html" "$base/" >/dev/null
expect "GET /: content-type" "$(values "$work/index-h" content-type)" "text/html; charset=utf-8"

if head -c 15 "$work/index.html" | tr '[:upper:]' '[:lower:]' | grep -q '^<!doctype html>'; then
  ok "GET /: the body is an HTML document"
else
  fail "GET /: the body is no HTML document"
fi

script=$(sed -n 's/.*<script[^>]* src="\([^"]*\)".*/\1/p' "$work/index.html" | head -n 1)
style=$(sed -n 's/.*<link[^>]*rel="stylesheet"[^>]* href="\([^"]*\)".*/\1/p' "$work/index.html" | head -n 1)

if [ -z "$script" ] || [ -z "$style" ]; then
  fail "index.html names no script or no style asset"
else
  fetch "$work/h" "$work/b" "$base$script" >/dev/null
  expect "GET $script: content-type" "$(values "$work/h" content-type)" "text/javascript; charset=utf-8"
  fetch "$work/h" "$work/b" "$base$style" >/dev/null
  expect "GET $style: content-type" "$(values "$work/h" content-type)" "text/css; charset=utf-8"
fi

# The icon of the SPA is an XML type, which carries the charset as well.
icon=$(sed -n 's/.*<link[^>]*rel="icon"[^>]* href="\([^"]*\)".*/\1/p' "$work/index.html" | head -n 1)

if [ -n "$icon" ]; then
  fetch "$work/h" "$work/b" "$base$icon" >/dev/null
  expect "GET $icon: content-type" "$(values "$work/h" content-type)" "image/svg+xml; charset=utf-8"
else
  fail "index.html names no icon"
fi

# The SPA works under the CSP: index.html holds no inline script or style.
# Each script tag counts on its own, also next to another on one line.
inline_scripts=$(sh "$(dirname "$0")/count-inline-scripts.sh" "$work/index.html")

if [ "$inline_scripts" -gt 0 ]; then
  fail "index.html holds $inline_scripts inline scripts"
elif grep -qi '<style\| style=' "$work/index.html"; then
  fail "index.html holds an inline style"
else
  ok "index.html holds no inline script or style"
fi

# The transaction cookie of the /auth/oidc pipeline (README section 6.5).
if [ -n "${CHECK_CONTAINER:-}" ]; then
  options=$(docker exec "$CHECK_CONTAINER" /app/bin/espalier eval \
    'IO.inspect(Keyword.drop(EspalierWeb.TransactionCookie.session_options(), [:signing_salt, :encryption_salt]))' 2>/dev/null | tr '\n' ' ')

  for option in 'key: "__Host-espalier_tx"' 'secure: true' 'http_only: true' \
    'same_site: "Lax"' 'path: "/"' 'max_age: 600'; do
    case $options in
      *"$option"*) ok "TransactionCookie.session_options/0: $option" ;;
      *) fail "TransactionCookie.session_options/0 lacks $option: $options" ;;
    esac
  done

  case $options in
    *"domain:"*) fail "TransactionCookie.session_options/0 sets a domain" ;;
    *) ok "TransactionCookie.session_options/0: no domain" ;;
  esac
else
  echo "skip  TransactionCookie.session_options/0: CHECK_CONTAINER is not set"
fi

if [ -n "${CHECK_OIDC_PROVIDER:-}" ]; then
  fetch "$work/h" "$work/b" "$base/auth/oidc/$CHECK_OIDC_PROVIDER" >/dev/null
  check_cookie "__Host-espalier_tx" "$(cookie_line "$work/h" __Host-espalier_tx)" lax 600
else
  echo "skip  Set-Cookie of GET /auth/oidc/<key>: CHECK_OIDC_PROVIDER is not set"
fi

if [ "$failures" -gt 0 ]; then
  echo "check-headers: $failures checks failed against $base" >&2
  exit 1
fi

echo "check-headers: every check passed against $base"
