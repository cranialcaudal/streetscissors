# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - builder: hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231004-slim
#   - runner: debian:bookworm-20231009-slim

ARG BUILDER_IMAGE="docker.io/library/elixir:1.15.7"
ARG RUNNER_IMAGE="docker.io/debian:bookworm-slim"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs ./
RUN mix deps.get --only $MIX_ENV

COPY config config
RUN mix deps.compile

COPY lib lib
RUN mix compile

COPY assets assets
COPY priv priv
RUN mix assets.deploy

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/web ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini. If an init process is not currently
# available, you can add one by supplying `install_before_1` to `mix phx.gen.release`
# See https://github.com/fenollp/erlang-tini for more details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/web", "start"]
