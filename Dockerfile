# syntax=docker/dockerfile:1
#
# Multi-stage build: compile the Rust NIF and Elixir release on the
# hexpm/elixir Debian image, then copy the release into Debian slim.
# Keep the Debian release of BUILDER_IMAGE and RUNNER_IMAGE identical so the
# NIF and ERTS link against the same glibc/OpenSSL.

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.16
ARG DEBIAN_VERSION=bookworm-20260824-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# git: Cargo fetches replay-core from GitHub (git-fetch-with-cli).
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Rust toolchain for the Rustler NIF (native/replay_parser).
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time config first so dependency compilation is cached.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY native native
COPY priv priv
COPY lib lib

# Builds the NIF in release mode via Rustler, then the app.
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

# --- Runtime image -----------------------------------------------------------
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses5 locales ca-certificates sqlite3 \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app && mkdir -p /data && chown nobody /data

ENV MIX_ENV="prod" PHX_SERVER=true DATABASE_PATH=/data/broodwar.db

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/broodwar ./

USER nobody

EXPOSE 4000

# Migrations run on boot (Ecto.Migrator in Broodwar.Application).
CMD ["/app/bin/broodwar", "start"]
