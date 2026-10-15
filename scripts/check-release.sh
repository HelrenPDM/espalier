#!/bin/sh
# Checks the production image and the running release of compose.yaml and
# fails on any finding (task 0017, step 6). Run it from the repository root;
# scripts/smoke.sh runs it against its own instance.
#
#   scripts/check-release.sh
#
# Environment:
#   ESPALIER_IMAGE   the image (default espalier:latest)
#   CHECK_CONTAINER  the running application container
#   CHECK_DB         the running database container of compose.yaml
#   BASE_URL         the application without proxy (default http://localhost:4000)
#   SECRET_ENV_FILE  an env file whose values existed when the image was
#                    built, such as the .env of the operator; no value of its
#                    secret variables may appear in the image metadata
#                    (default ENV_FILE, default .env). An empty value skips
#                    this comparison.
#   ENV_FILE         the env file of the instance, the default of
#                    SECRET_ENV_FILE
set -eu

image=${ESPALIER_IMAGE:-espalier:latest}
base=${BASE_URL:-http://localhost:4000}
secret_file=${SECRET_ENV_FILE-${ENV_FILE:-.env}}
# The work files hold secret values, readable by this user alone.
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

: "${CHECK_CONTAINER:?set CHECK_CONTAINER to the application container}"
: "${CHECK_DB:?set CHECK_DB to the database container}"

ok() { echo "ok    $1"; }

fail() {
  echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

# No repository metadata in the image (ASVS 13.4.1).
# root reads every directory of the image.
found=$(docker run --rm --user 0 --entrypoint find "$image" / -xdev \( -name .git -o -name .svn \) -print)
if [ -z "$found" ]; then ok "no .git or .svn directory in $image"; else fail "repository metadata in $image: $found"; fi

# No env file in the image (ASVS 13.3.1), which .dockerignore keeps out of the
# build context.
found=$(docker run --rm --user 0 --entrypoint find "$image" / -xdev \( -name .env -o -name '.env.*' \) -print)
if [ -z "$found" ]; then ok "no .env file in $image"; else fail "env files in $image: $found"; fi

# No Erlang distribution cookie in the image: rel/env.sh.eex generates one for
# each command while distribution is off and requires RELEASE_COOKIE when it
# is on.
found=$(docker run --rm --user 0 --entrypoint find "$image" /app/releases -maxdepth 1 -name COOKIE -print)
if [ -z "$found" ]; then ok "no /app/releases/COOKIE in $image"; else fail "$image holds $found"; fi

# Below /app, root owns every file and no group or other user may write.
found=$(docker run --rm --user 0 --entrypoint find "$image" /app \( ! -user 0 -o -perm /022 \) ! -type l -print)
if [ -z "$found" ]; then ok "root owns /app, and no group or other user may write there"; else fail "writable or not owned by root in $image: $(printf '%s\n' "$found" | head -n 5)"; fi

if docker run --rm --network none -e RELEASE_DISTRIBUTION=sname --entrypoint /app/bin/espalier \
  "$image" version >"$work/cookie.out" 2>&1; then
  fail "bin/espalier runs with RELEASE_DISTRIBUTION=sname and without RELEASE_COOKIE"
elif grep -q RELEASE_COOKIE "$work/cookie.out"; then
  ok "bin/espalier refuses RELEASE_DISTRIBUTION=sname without RELEASE_COOKIE"
else
  fail "bin/espalier with RELEASE_DISTRIBUTION=sname: $(cat "$work/cookie.out")"
fi

# No value of a secret variable in the image configuration or its history
# (ASVS 13.3.1), and no secret defined as ENV or ARG. The values come from an
# env file that existed at build time; the secrets of an instance that
# scripts/fill-secrets.sh wrote after the build cannot be in the image. grep
# reads them from a file, so that no value appears in the arguments of a
# process.
docker image inspect "$image" >"$work/inspect"
docker history --no-trunc "$image" >"$work/history"
secret_names='SECRET_KEY_BASE|CLOAK_KEY_V[0-9]+|CLOAK_HMAC_SECRET|POSTGRES_PASSWORD|DATABASE_URL|SMTP_PASSWORD|AUTH_[A-Z0-9_]+_(CLIENT_SECRET|BIND_PASSWORD)|WEBHOOK_SECRET_[A-Z0-9_]+|RELEASE_COOKIE'

if [ -z "$secret_file" ]; then
  echo "skip  secret values in the image metadata: SECRET_ENV_FILE names no env file from before the build"
elif [ -f "$secret_file" ]; then
  # An empty line would match every line, so the list holds none.
  grep -E "^($secret_names)=" "$secret_file" | cut -d= -f2- | sed 's/^"//; s/"$//' | grep -v '^$' >"$work/secrets" || true
  count=$(wc -l <"$work/secrets" | tr -d ' ')

  if [ "$count" -eq 0 ]; then
    echo "skip  secret values in the image metadata: $secret_file holds no secret value"
  elif grep -qF -f "$work/secrets" "$work/inspect" "$work/history"; then
    fail "a secret value of $secret_file appears in the image metadata"
  else
    ok "no value of the $count secret variables of $secret_file in the image metadata"
  fi
else
  fail "$secret_file is missing, so the secret values cannot be compared"
fi

if grep -Eq "\"($secret_names)=" "$work/inspect" || grep -Eq "(ENV|ARG) ($secret_names)" "$work/history"; then
  fail "the image defines a secret variable as ENV or ARG"
else
  ok "no secret variable defined as ENV or ARG"
fi

# LICENSE and NOTICE unchanged at /app (Apache License 2.0, section 4).
for file in LICENSE NOTICE; do
  if docker run --rm --entrypoint cat "$image" "/app/$file" | cmp -s - "$file"; then
    ok "/app/$file equals $file"
  else
    fail "/app/$file differs from $file or is missing"
  fi
done

# No development route, mock provider, development controller, debug error
# page, code reloader or TRACE route, and no documentation or monitoring
# endpoint besides /api/openapi and /health (ASVS 13.4.2, 13.4.4, 13.4.5,
# 15.2.3). The eval node of the release loads the code and the configuration
# without starting the application. It never starts distribution itself, so
# it checks the RELEASE_DISTRIBUTION that the container passes to the release
# and to bin/espalier. It also reads config/runtime.exs of the release once
# more with SMTP_HOST set and checks the mail transport: a direct connection
# to SMTP_HOST without MX lookup, and STARTTLS with TLS 1.2 or 1.3 and
# certificate and host name verification (ASVS 12.3.1).
code=$(
  cat <<'EOF'
routes = Phoenix.Router.routes(EspalierWeb.Router)
paths = Enum.map(routes, & &1.path)
endpoint = Application.get_env(:espalier, EspalierWeb.Endpoint, [])

System.put_env("SMTP_HOST", "smtp.example.org")
System.put_env("MAIL_FROM", "Espalier <noreply@example.org>")
[runtime] = Path.wildcard("/app/releases/*/runtime.exs")
mailer = Config.Reader.read!(runtime, env: :prod, target: :host)[:espalier][Espalier.Mailer]
tls = mailer[:tls_options] || []

checks = [
  {"no /dev or /api/dev route",
   not Enum.any?(paths, &(String.starts_with?(&1, "/dev") or String.starts_with?(&1, "/api/dev")))},
  {"Espalier.DevOidc is not loaded", not Code.ensure_loaded?(Espalier.DevOidc)},
  {"EspalierWeb.DevE2EController is not loaded",
   not Code.ensure_loaded?(EspalierWeb.DevE2EController)},
  {"debug_errors is not set", endpoint[:debug_errors] != true},
  {"code_reloader is not set", endpoint[:code_reloader] != true},
  {"no TRACE route", not Enum.any?(routes, &(&1.verb == :trace))},
  {"no route path names dashboard, swagger, metrics, docs or mailbox",
   not Enum.any?(paths, &String.contains?(String.downcase(&1), ~w(dashboard swagger metrics docs mailbox)))},
  {"/api/openapi and /health are routes", "/api/openapi" in paths and "/health" in paths},
  {"RELEASE_DISTRIBUTION is none", System.get_env("RELEASE_DISTRIBUTION") == "none"},
  {"SMTP: no MX lookup, STARTTLS with TLS 1.2 or 1.3 and certificate and host name verification",
   mailer[:adapter] == Swoosh.Adapters.SMTP and mailer[:no_mx_lookups] == true and
     mailer[:tls] == :always and tls[:verify] == :verify_peer and
     tls[:versions] == [:"tlsv1.2", :"tlsv1.3"] and
     tls[:server_name_indication] == ~c"smtp.example.org" and
     is_list(tls[:customize_hostname_check])}
]

for {label, passed?} <- checks do
  IO.puts(if passed?, do: "ok    #{label}", else: "FAIL  #{label}")
end
EOF
)

docker exec "$CHECK_CONTAINER" /app/bin/espalier eval "$code" >"$work/release.out" 2>&1 || true

checks=$(grep -c '^ok    ' "$work/release.out" || true)
if [ "$checks" -eq 10 ]; then
  sed 's/^ok    /ok    release: /' "$work/release.out" | grep '^ok'
else
  fail "release checks: $(cat "$work/release.out")"
fi

# RELEASE_DISTRIBUTION=none of rel/env.sh.eex holds in the running release:
# nothing listens on the port of epmd (4369, hex 1111).
if docker exec "$CHECK_CONTAINER" cat /proc/net/tcp /proc/net/tcp6 | awk '$4 == "0A" { print $2 }' | grep -qi ':1111$'; then
  fail "a process of $CHECK_CONTAINER listens on the epmd port 4369"
else
  ok "no listener on the epmd port 4369 in $CHECK_CONTAINER"
fi

# No BEAM process of the container runs with a node name, which the release
# script passes as -sname or -name when distribution is on. The host filters
# the command lines, so that the pattern matches no process of its own.
docker exec "$CHECK_CONTAINER" sh -c 'for p in /proc/[0-9]*; do tr "\0" " " <"$p/cmdline" 2>/dev/null; echo; done' |
  grep beam.smp >"$work/beam" || true

if [ ! -s "$work/beam" ]; then
  fail "no beam.smp process in $CHECK_CONTAINER"
elif grep -Eq -- ' -s?name ' "$work/beam"; then
  fail "a beam.smp process of $CHECK_CONTAINER runs with -sname or -name"
else
  ok "no beam.smp process of $CHECK_CONTAINER runs with -sname or -name"
fi

# The health check of the image asks the port of PORT, read as
# config/runtime.exs reads it: a padded and quoted value of the port that the
# endpoint listens on passes, and another port fails.
if docker exec "$CHECK_CONTAINER" /app/bin/health >/dev/null 2>&1 &&
  docker exec -e PORT=' "4000" ' "$CHECK_CONTAINER" /app/bin/health >/dev/null 2>&1 &&
  ! docker exec -e PORT=4001 "$CHECK_CONTAINER" /app/bin/health >/dev/null 2>&1; then
  ok "bin/health asks the port of PORT"
else
  fail "bin/health does not follow PORT"
fi

health=$(docker inspect -f '{{json .Config.Healthcheck.Test}}' "$CHECK_CONTAINER")
if [ "$health" = '["CMD","/app/bin/health"]' ]; then
  ok "the health check of the image runs bin/health"
else
  fail "the health check of the image is $health"
fi

# A directory of the static files returns no listing: 404, or the index.html
# of the SPA catch-all (ASVS 13.4.3).
curl -sS --max-time 20 -o "$work/index.html" "$base/"

for path in /spa/assets/ /spa/ /assets/; do
  status=$(curl -sS --max-time 20 -o "$work/dir" -w '%{http_code}' "$base$path")

  if [ "$status" = 404 ] || { [ "$status" = 200 ] && cmp -s "$work/dir" "$work/index.html"; }; then
    ok "GET $path returns no listing ($status)"
  else
    fail "GET $path returns $status with a body other than index.html"
  fi
done

# Error bodies carry a code without internals (ASVS 13.4.2).
status=$(curl -sS --max-time 20 -o "$work/b" -w '%{http_code}' "$base/api/does-not-exist")
body=$(cat "$work/b")

if [ "$status" = 404 ] && [ "$body" = '{"error":"not_found"}' ]; then
  ok "GET /api/does-not-exist answers 404 with the code not_found"
else
  fail "GET /api/does-not-exist answers $status with $body"
fi

body=$(curl -sS --max-time 20 "$base/health")
if [ "$body" = '{"status":"ok"}' ]; then ok "GET /health returns only its status"; else fail "GET /health returns $body"; fi

# TRACE: a 4xx answer that echoes no request header (ASVS 13.4.4).
status=$(curl -sS --max-time 20 -X TRACE -H 'X-Trace-Probe: espalier-trace-probe' -o "$work/b" -w '%{http_code}' "$base/")

case $status in
  4??)
    if grep -q espalier-trace-probe "$work/b"; then
      fail "TRACE echoes a request header"
    else
      ok "TRACE answers $status without an echo"
    fi
    ;;
  *) fail "TRACE answers $status" ;;
esac

# Every client connection to PostgreSQL uses TLS (ASVS 12.3.1).
query="select count(*) from pg_stat_ssl s join pg_stat_activity a using (pid) where a.client_addr is not null and"
plain=$(docker exec "$CHECK_DB" psql -U postgres -Atc "$query not s.ssl")
tls=$(docker exec "$CHECK_DB" psql -U postgres -Atc "$query s.ssl")

if [ "$plain" = 0 ] && [ "$tls" -ge 1 ]; then
  ok "database: $tls client connections with TLS, none without"
else
  fail "database: $plain client connections without TLS, $tls with TLS"
fi

if [ "$failures" -gt 0 ]; then
  echo "check-release: $failures checks failed" >&2
  exit 1
fi

echo "check-release: every check passed"
