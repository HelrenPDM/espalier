# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.4-erlang-28.5.0.7-debian-trixie-20261005-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20261005-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20261005-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker?repo=hexpm/elixir&os=debian&sort=elixir_version,erlang_version,os_version
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=28.5.0.7
ARG DEBIAN_VERSION=trixie-20261005-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# build the SPA with Vite (base /spa/) and the player of the SCORM packages
FROM node:24-trixie-slim AS frontend
WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
# tsc -b checks the tests of src/ as well, and the evaluator test imports the
# shared cases of the server and the browser evaluator from test/fixtures/.
COPY test/fixtures/evaluator_cases.json /test/fixtures/
RUN npm run build -- --outDir /out/spa
# The SCORM build reads LICENSE and NOTICE from the parent directory of
# /frontend, as it does in the repository, and fails without them.
COPY LICENSE NOTICE /
RUN npm run build:scorm -- --outDir /out/scorm_player

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY --from=frontend /out/spa priv/static/spa
COPY --from=frontend /out/scorm_player priv/scorm_player
# The demo pack for Espalier.Release.seed_demo/0, the only content pack of
# the image; organizations import their own packs after deployment.
COPY content/demo priv/demo_pack

COPY lib lib

# Compile the release
RUN mix compile

# Fetch the schema files of the SCORM packages, which the repository does
# not hold (priv/scorm/xsd/SOURCE.md), and check them against their SHA-256.
RUN mix espalier.scorm_xsd

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
# mix release writes a random distribution cookie to releases/COOKIE. A file
# in any layer of the image is known to everyone who holds the image, and a
# later RUN rm in the final stage would leave it in the layer of the copy, so
# the builder removes it before the copy. rel/env.sh.eex generates a cookie
# for each command while distribution is off and requires RELEASE_COOKIE when
# it is on.
# chmod removes the group and other write bits that the files carry from a
# checkout with the umask 002, so that no user of the group root (gid 0, the
# group of a uid without a passwd entry) can change the release.
RUN mix release \
  && rm _build/${MIX_ENV}/rel/espalier/releases/COOKIE \
  && chmod -R go-w _build/${MIX_ENV}/rel/espalier

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# curl serves the health check below.
RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage. The release belongs to
# root, so the runtime user nobody can neither change nor replace a file of
# it. The release writes nothing below /app: sys.config holds no
# RUNTIME_CONFIG=true, so bin/espalier writes no runtime configuration to
# RELEASE_TMP (default /app/tmp), and System.tmp_dir!/0 is /tmp.
COPY --from=builder /app/_build/${MIX_ENV}/rel/espalier ./

# The image redistributes the work in object form, so it carries the license
# text and the attribution notices (Apache License 2.0, sections 4 a and
# 4 d). Both files belong to root.
COPY --chmod=0644 LICENSE NOTICE ./

# The SCORM packages of the export (EXPORT_DIR=/data/exports in compose.yaml).
# The group root may write as well, for a container that runs with another
# uid and the gid 0.
RUN mkdir -p /data/exports && chown nobody:0 /data/exports && chmod 0770 /data/exports

EXPOSE 4000

# bin/health asks /health on the port of PORT, read as config/runtime.exs
# reads it (rel/overlays/bin/health).
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD ["/app/bin/health"]

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
