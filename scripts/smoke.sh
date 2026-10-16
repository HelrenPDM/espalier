#!/bin/sh
# Smoke test of the production image (task 0017, step 9). It needs Docker
# with the Compose plugin, curl and a POSIX shell, and runs from any
# directory of the repository.
#
#   scripts/smoke.sh [--proxy]
#
# The script writes tmp/smoke.env from .env.demo.example with secrets read
# from /dev/urandom and starts compose.yaml under the project name
# espalier-smoke, so that the .env and the volumes of a developer stay
# untouched. It waits for /health, runs bin/migrate and
# Espalier.Release.seed_demo(), checks the line of the effective settings in
# the log of the boot, runs scripts/check-headers.sh and
# scripts/check-release.sh, checks ffmpeg and its encoders in the container,
# signs in as a demo person, checks that GET /api/policies lists
# usage-policy, loads the demo program, answers one item, waits until the
# media of the demo pack are ready and checks the media route on the SVG and
# the WebM of the demo (task 0018): the content type, the media CSP,
# content-disposition, nosniff, cache-control, accept-ranges and the etag,
# 206 for a range and 404 for Sec-Fetch-Dest: script. It then removes the
# instance with its volumes.
#
# --proxy adds the Caddy example of docs/guides/examples/compose.caddy.yaml
# with SITE_ADDRESS=localhost and local accounts, runs
# scripts/check-headers.sh against the proxy with the local root certificate
# of Caddy, checks that the address that Caddy saw reaches the log and a
# client's X-Forwarded-For value never does, and sends two request
# smuggling probes through the proxy and directly to Bandit.
#
# Environment:
#   ESPALIER_IMAGE  the image (default espalier:latest, make docker-build)
#   APP_PORT        loopback port of the application (default 4000)
#   HTTPS_PORT      published port of Caddy with --proxy (default 443)
#   PROXY_SUBNET    subnet of the proxy network (default 172.30.0.0/24)
#   PROXY_ADDRESS   address of Caddy in it (default 172.30.0.10)
#   PROBE_ADDRESS   address of the probe container in it (default 172.30.0.20)
#   SMOKE_KEEP      true leaves the instance running after the test
set -eu

cd "$(dirname "$0")/.."

proxy=false
case ${1:-} in
  "") ;;
  --proxy) proxy=true ;;
  *)
    echo "usage: $0 [--proxy]" >&2
    exit 2
    ;;
esac

export ESPALIER_IMAGE="${ESPALIER_IMAGE:-espalier:latest}"
export APP_PORT="${APP_PORT:-4000}"
export ENV_FILE=tmp/smoke.env
export SITE_ADDRESS=localhost
export HTTPS_PORT="${HTTPS_PORT:-443}"
export PROXY_SUBNET="${PROXY_SUBNET:-172.30.0.0/24}"
export PROXY_ADDRESS="${PROXY_ADDRESS:-172.30.0.10}"
# Docker Compose takes POSTGRES_PASSWORD from the shell before the env file,
# while app reads DATABASE_URL from the env file alone, so a value of the
# shell would give db another password.
unset POSTGRES_PASSWORD
probe_address=${PROBE_ADDRESS:-172.30.0.20}
project=espalier-smoke
base=http://localhost:$APP_PORT
caddy_root=tmp/caddy-root.crt

if [ "$HTTPS_PORT" = 443 ]; then
  public_url=https://localhost
else
  public_url=https://localhost:$HTTPS_PORT
fi

compose() {
  if [ "$proxy" = true ]; then
    docker compose --env-file "$ENV_FILE" -p "$project" -f compose.yaml \
      -f docs/guides/examples/compose.caddy.yaml "$@"
  else
    docker compose --env-file "$ENV_FILE" -p "$project" -f compose.yaml "$@"
  fi
}

work=$(mktemp -d)
failures=0

cleanup() {
  status=$?

  if [ "$status" -ne 0 ]; then
    echo "smoke: the last lines of the application log:" >&2
    compose logs --no-color --tail 30 app >&2 2>/dev/null || true
  fi

  if [ "${SMOKE_KEEP:-false}" = true ]; then
    echo "smoke: the instance keeps running; remove it with docker compose -p $project down -v"
  else
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi

  rm -rf "$work"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 1' INT TERM

step() { echo "smoke: $1"; }
ok() { echo "ok    $1"; }

fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

# set_variable NAME VALUE: replaces or appends NAME in the env file.
set_variable() {
  if grep -q "^$1=" "$ENV_FILE"; then
    sed "s|^$1=.*|$1=$2|" "$ENV_FILE" >"$work/env"
  else
    cat "$ENV_FILE" >"$work/env"
    echo "$1=$2" >>"$work/env"
  fi

  cat "$work/env" >"$ENV_FILE"
}

wait_for() {
  tries=0

  until curl -fsS --max-time 5 "$@" >/dev/null 2>&1; do
    tries=$((tries + 1))

    if [ "$tries" -ge 90 ]; then
      echo "smoke: no answer from $*" >&2
      exit 1
    fi

    sleep 2
  done
}

step "writing $ENV_FILE from .env.demo.example"
mkdir -p tmp
rm -f "$ENV_FILE"
scripts/fill-secrets.sh .env.demo.example "$ENV_FILE" >/dev/null
set_variable PHX_HOST localhost
set_variable PUBLIC_URL "$public_url"

if [ "$proxy" = true ]; then
  # The X-Forwarded-For check signs in with a password, and the application
  # trusts the header from Caddy alone.
  set_variable LOCAL_ACCOUNTS true
  set_variable TRUSTED_PROXIES "$PROXY_ADDRESS"
fi

step "starting $ESPALIER_IMAGE as project $project"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d
wait_for "$base/health"

step "bin/migrate and Espalier.Release.seed_demo()"
compose exec -T app bin/migrate >"$work/migrate.log" 2>&1 || {
  cat "$work/migrate.log" >&2
  exit 1
}
compose exec -T app bin/espalier eval 'Espalier.Release.seed_demo()' >"$work/seed.log" 2>&1 || true

if grep -q '^Seeded ' "$work/seed.log"; then
  ok "$(grep '^Published ' "$work/seed.log")"
else
  cat "$work/seed.log" >&2
  exit 1
fi

# The boot logs the effective settings once, with values and without a
# secret (task 0017, step 4); the demo profile sets TRACKING_DETAIL=minimal
# and AUTH_DEMO=true. grep reads the secret values from a file, so that none
# appears in the arguments of a process.
compose logs --no-color app >"$work/app.log" 2>&1
grep 'Effective settings:' "$work/app.log" >"$work/settings" || true
grep -E '^(SECRET_KEY_BASE|CLOAK_KEY_V1|CLOAK_HMAC_SECRET|POSTGRES_PASSWORD)=' "$ENV_FILE" |
  cut -d= -f2- | grep -v '^$' >"$work/secrets" || true
lines=$(wc -l <"$work/settings" | tr -d ' ')

if [ "$lines" -ne 1 ]; then
  fail "the log of app holds $lines lines with Effective settings:, not one"
elif ! grep -q ' TRACKING_DETAIL=minimal[ ;]' "$work/settings" ||
  ! grep -q ' AUTH_DEMO=true[ ;]' "$work/settings"; then
  fail "the effective settings lack TRACKING_DETAIL=minimal or AUTH_DEMO=true: $(cat "$work/settings")"
elif grep -qF -f "$work/secrets" "$work/settings"; then
  fail "the line of the effective settings holds a secret value of $ENV_FILE"
else
  ok "the boot logs one line Effective settings: with TRACKING_DETAIL=minimal and AUTH_DEMO=true and no secret"
fi

app=$(compose ps -q app)
db=$(compose ps -q db)

# The application port is published on the loopback address only, so no
# endpoint answers over plain HTTP from another host (ASVS 4.1.2).
published=$(docker port "$app" | tr '\n' ' ')
case $published in
  "4000/tcp -> 127.0.0.1:$APP_PORT ") ok "app publishes port 4000 on 127.0.0.1:$APP_PORT only" ;;
  *) fail "app publishes '$published'" ;;
esac

step "scripts/check-headers.sh $base"
PUBLIC_URL=$public_url CHECK_CONTAINER=$app scripts/check-headers.sh "$base" || failures=$((failures + 1))

# The secrets of $ENV_FILE came into being after the image, so the value
# comparison takes the .env of the checkout, which existed next to the build
# context, and is skipped without one.
if [ -f .env ]; then secret_env_file=.env; else secret_env_file=; fi

step "scripts/check-release.sh"
SECRET_ENV_FILE=$secret_env_file CHECK_CONTAINER=$app CHECK_DB=$db BASE_URL=$base \
  scripts/check-release.sh || failures=$((failures + 1))

# request METHOD PATH [JSON]: one request with the session cookie, and for a
# body with Origin and the CSRF token; prints the status code.
cookie=
csrf=

request() {
  if [ "$#" -ge 3 ]; then
    curl -sS --max-time 20 -D "$work/h" -o "$work/b" -w '%{http_code}' -X "$1" \
      -H "Origin: $public_url" -H "x-csrf-token: $csrf" -H "Cookie: $cookie" \
      -H "content-type: application/json" --data "$3" "$base$2"
  else
    curl -sS --max-time 20 -D "$work/h" -o "$work/b" -w '%{http_code}' -X "$1" \
      -H "Cookie: $cookie" "$base$2"
  fi
}

# Takes a new session cookie and CSRF token from the last answer.
keep_session() {
  value=$(tr -d '\r' <"$work/h" | awk 'tolower(substr($0, 1, 11)) == "set-cookie:" { print substr($0, 13) }' |
    grep '^__Host-espalier=' | head -n 1 | cut -d';' -f1)
  [ -z "$value" ] || cookie=$value
  value=$(sed -n 's/.*"csrf_token":"\([^"]*\)".*/\1/p' "$work/b")
  [ -z "$value" ] || csrf=$value
}

# expect_status LABEL STATUS WANTED...: records a failure and goes on.
expect_status() {
  label=$1
  status=$2
  shift 2

  for wanted in "$@"; do
    if [ "$status" = "$wanted" ]; then
      ok "$label ($status)"
      return 0
    fi
  done

  fail "$label: status $status, body $(head -c 300 "$work/b")"
}

step "ffmpeg in the container"
if compose exec -T app ffmpeg -hide_banner -version >"$work/ffmpeg.txt" 2>&1; then
  ok "$(head -n 1 "$work/ffmpeg.txt")"
else
  fail "ffmpeg -version: $(head -c 300 "$work/ffmpeg.txt")"
fi

compose exec -T app ffmpeg -hide_banner -encoders >"$work/encoders.txt" 2>&1 || true
for encoder in libvpx-vp9 libopus libwebp libwebp_anim; do
  if grep -q " $encoder " "$work/encoders.txt"; then
    ok "ffmpeg has the encoder $encoder"
  else
    fail "ffmpeg lacks the encoder $encoder"
  fi
done

step "demo sign-in and the demo program"
expect_status "GET /api/session" "$(request GET /api/session)" 200
keep_session
expect_status "POST /api/auth/demo" "$(request POST /api/auth/demo '{"slot":1}')" 200
keep_session
expect_status "GET /api/session" "$(request GET /api/session)" 200

if grep -q '"demo":true' "$work/b" && grep -q '"strength":"demo"' "$work/b"; then
  ok "the session is a demo session, and flags.demo is true"
else
  fail "the session after the demo sign-in: $(head -c 300 "$work/b")"
fi

expect_status "GET /api/policies" "$(request GET /api/policies)" 200

if grep -q '"key":"usage-policy"' "$work/b"; then
  ok "GET /api/policies lists usage-policy"
else
  fail "GET /api/policies does not list usage-policy"
fi

slug=ai-assistant-basics-demo
expect_status "GET /api/programs" "$(request GET /api/programs)" 200
grep -q "\"slug\":\"$slug\"" "$work/b" || fail "GET /api/programs does not list $slug"

expect_status "POST /api/enrollments" \
  "$(request POST /api/enrollments "{\"program_slug\":\"$slug\",\"path\":\"full\"}")" 201

expect_status "GET /api/programs/$slug" "$(request GET "/api/programs/$slug")" 200
module=$(sed -n 's/.*"modules":\[{"id":"\([0-9a-f-]*\)".*/\1/p' "$work/b")

if [ -n "$module" ]; then
  expect_status "GET /api/modules/$module" "$(request GET "/api/modules/$module")" 200
else
  fail "GET /api/programs/$slug names no module"
fi

# The first single_choice item of the practice items of the module and the
# key of its first option; exam items take answers through an attempt.
# After a split at each "{", an item object starts a line with its id, its
# options follow without an id, and its kind follows the options.
item=$(tr '{' '\n' <"$work/b" | awk '
  index($0, "\"practice_items\":[") { practice = 1; next }
  !practice { next }
  match($0, /^"id":"[0-9a-f-]+"/) { id = substr($0, 7, RLENGTH - 7); key = "" }
  key == "" && match($0, /"key":"[a-z0-9-]+"/) { key = substr($0, RSTART + 7, RLENGTH - 8) }
  index($0, "\"kind\":\"single_choice\"") && id != "" && key != "" { print id " " key; exit }')

if [ -n "$item" ]; then
  expect_status "POST /api/items/${item% *}/responses" \
    "$(request POST "/api/items/${item% *}/responses" "{\"answer\":{\"options\":[\"${item#* }\"]}}")" 200 201
else
  fail "the module holds no single_choice item"
fi

# The media of the demo pack (task 0018): the import of seed_demo processes
# them, and the module views name them once they are ready.
step "the media route on the media of the demo pack"
modules=$(request GET "/api/programs/$slug" >/dev/null && grep -o '"id":"[0-9a-f-]*","number":[0-9]*' "$work/b" | sed 's/"id":"\([0-9a-f-]*\)".*/\1/')
media=
tries=0
while [ -z "$media" ] && [ "$tries" -lt 60 ]; do
  found=
  for id in $modules; do
    request GET "/api/modules/$id" >/dev/null
    found="$found $(grep -o '/media/[0-9a-f]\{64\}\.\(svg\|webm\)' "$work/b" | sort -u | tr '\n' ' ')"
  done
  case $found in
    *.svg*.webm* | *.webm*.svg*) media=$found ;;
    *) tries=$((tries + 1)); sleep 2 ;;
  esac
done

if [ -z "$media" ]; then
  fail "the module views name no ready SVG and WebM of the demo pack"
fi

media_csp="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; sandbox"

for url in $media; do
  case $url in
    *.svg)
      dest=image
      media_type="image/svg+xml; charset=utf-8"
      ;;
    *)
      dest=video
      media_type=video/webm
      ;;
  esac

  expect_status "GET $url" "$(request GET "$url")" 200
  headers=$(tr -d '\r' <"$work/h")

  # Each header line must match in full, so a type with a missing or an
  # extra parameter fails.
  for wanted in "content-type: $media_type" "content-security-policy: $media_csp" \
    "content-disposition: inline; filename=\"${url##*/}\"" "x-content-type-options: nosniff" \
    "cache-control: private, max-age=31536000, immutable" "accept-ranges: bytes"; do
    if printf '%s\n' "$headers" | grep -qixF "$wanted"; then
      ok "GET $url: $wanted"
    else
      fail "GET $url lacks '$wanted'"
    fi
  done

  if printf '%s\n' "$headers" | grep -qi '^etag: "[0-9a-f]\{64\}"$'; then
    ok "GET $url: a quoted etag"
  else
    fail "GET $url: no quoted etag"
  fi

  status=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -H "Cookie: $cookie" \
    -H "Range: bytes=0-99" -H "Sec-Fetch-Dest: $dest" "$base$url")
  expect_status "GET $url with Range: bytes=0-99" "$status" 206

  status=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -H "Cookie: $cookie" \
    -H "Sec-Fetch-Dest: script" "$base$url")
  expect_status "GET $url with Sec-Fetch-Dest: script" "$status" 404
done

if [ "$proxy" = true ]; then
  step "behind the Caddy example at $public_url"

  tries=0
  until compose cp caddy:/data/caddy/pki/authorities/local/root.crt "$caddy_root" >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 30 ] || {
      echo "smoke: Caddy wrote no local root certificate" >&2
      exit 1
    }
    sleep 1
  done

  # Caddy publishes the HTTPS port alone (ASVS 4.1.2).
  ports=$(docker port "$(compose ps -q caddy)" | cut -d' ' -f1 | sort -u | tr '\n' ' ')
  if [ "$ports" = "443/tcp " ]; then
    ok "caddy publishes port 443 alone"
  else
    fail "caddy publishes the ports $ports"
  fi

  # The probe container runs as nobody and reads the public certificate.
  chmod 644 "$caddy_root"
  wait_for --cacert "$caddy_root" "$public_url/health"

  CHECK_CA_FILE=$caddy_root PUBLIC_URL=$public_url CHECK_CONTAINER=$app \
    scripts/check-headers.sh "$public_url" || failures=$((failures + 1))

  # A sign-in with unknown credentials from a container with a known address
  # on the proxy network, through Caddy and with a forged X-Forwarded-For
  # header. The log line authn_login_fail carries the address that Caddy
  # saw, and the forged value reaches no log line (ASVS 4.1.3, 15.3.4).
  forged=203.0.113.7
  docker run --rm --network "${project}_proxy" --ip "$probe_address" \
    -v "$PWD/$caddy_root:/tmp/caddy-root.crt:ro" --entrypoint /bin/sh "$ESPALIER_IMAGE" -c '
      set -eu
      address=$1
      fetch() { curl -sS --max-time 20 --cacert /tmp/caddy-root.crt --resolve "localhost:443:$address" "$@"; }
      fetch -D /tmp/h -o /tmp/b https://localhost/api/session
      cookie=$(tr -d "\r" </tmp/h | sed -n "s/^set-cookie: \(__Host-espalier=[^;]*\);.*/\1/p")
      csrf=$(sed -n "s/.*\"csrf_token\":\"\([^\"]*\)\".*/\1/p" /tmp/b)
      fetch -o /dev/null -w "%{http_code}" -X POST -H "Origin: $2" \
        -H "x-csrf-token: $csrf" -H "Cookie: $cookie" -H "content-type: application/json" \
        -H "X-Forwarded-For: $3" \
        --data "{\"email\":\"nobody@example.org\",\"password\":\"not-the-password-1\"}" \
        https://localhost/api/auth/password
    ' sh "$PROXY_ADDRESS" "$public_url" "$forged" >"$work/xff-status" || true
  sleep 1
  compose logs --no-color app >"$work/app.log" 2>&1

  if [ "$(cat "$work/xff-status")" = 401 ] &&
    grep '"event":"authn_login_fail"' "$work/app.log" | tail -n 1 | grep -q "\"ip\":\"$probe_address\""; then
    ok "authn_login_fail carries the address that Caddy saw ($probe_address)"
  else
    fail "authn_login_fail without the address $probe_address (status $(cat "$work/xff-status")): $(grep authn_login_fail "$work/app.log" | tail -n 1)"
  fi

  if grep -q "$forged" "$work/app.log"; then
    fail "the forged X-Forwarded-For value $forged reached the log"
  else
    ok "the forged X-Forwarded-For value reached no log line"
  fi

  # Request smuggling probes (ASVS 4.2.1) from a container of postgres:18,
  # which brings bash and openssl: two differing Content-Length values, and
  # Content-Length next to Transfer-Encoding: chunked with a complete inner
  # request for /api/smuggled in the single chunk. Each probe runs through
  # Caddy and directly to Bandit, and prints the status of every response
  # it receives within five seconds.
  probes=$(
    cat <<'EOF'
cl='POST /health HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 2\r\nContent-Length: 30\r\n\r\n{}'
inner='GET /api/smuggled HTTP/1.1\r\nHost: localhost\r\n\r\n'
size=$(printf "$inner" | wc -c)
te="POST /health HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n$(printf '%x' "$size")\r\n${inner}\r\n0\r\n\r\n"
proxy() { printf "$1" | timeout 5 openssl s_client -quiet -connect caddy:443 -servername localhost 2>/dev/null || true; }
bandit() { exec 3<>/dev/tcp/app/4000; printf "$1" >&3; timeout 5 cat <&3 || true; exec 3>&-; }
for probe in cl te; do
  for path in proxy bandit; do
    if [ "$probe" = cl ]; then request=$cl; else request=$te; fi
    statuses=$("$path" "$request" | tr -d '\r' | grep '^HTTP/1\.[01] ' | cut -d' ' -f2 | tr '\n' ' ')
    echo "$probe $path ${statuses% }"
  done
done
EOF
  )

  docker run --rm --network "${project}_proxy" --entrypoint /bin/bash postgres:18 -c "$probes" >"$work/probes"
  compose logs --no-color app >"$work/app.log" 2>&1

  for expected in "cl proxy" "cl bandit" "te proxy" "te bandit"; do
    line=$(grep "^$expected " "$work/probes" || true)
    statuses=${line#"$expected "}

    # One response each: 400 for two Content-Length values, and 400 or the
    # answer to the outer POST /health (404) for the chunked probe.
    case "$expected:$statuses" in
      "cl proxy:400" | "cl bandit:400" | "te proxy:400" | "te proxy:404" | "te bandit:400" | "te bandit:404")
        ok "framing probe $expected: one response ($statuses)"
        ;;
      *) fail "framing probe $expected: responses '$statuses'" ;;
    esac
  done

  if grep -q '/api/smuggled' "$work/app.log"; then
    fail "the inner request /api/smuggled reached the application"
  else
    ok "the inner request /api/smuggled reached no log line"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "smoke: $failures checks failed" >&2
  exit 1
fi

echo "smoke: every check passed"
