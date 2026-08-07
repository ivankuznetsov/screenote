# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Build it locally with:
# docker build -t screenote .
# Run the self-hosted image through compose.yaml so runtime secrets stay in restricted files.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Keep this immutable multi-architecture base in sync with .ruby-version. The
# release validator rejects a mutable or unexpected base reference.
FROM docker.io/library/ruby:3.4.10-alpine3.24@sha256:c5a5064d190055633011c03aa800170cc36945ff3afb5f6c915329f92d6f1e00 AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apk add --no-cache \
      age \
      bash \
      coreutils \
      curl \
      jemalloc \
      postgresql-client \
      sqlite \
      tar \
      tzdata \
      vips

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    MAX_REQUEST_BODY="31457280" \
    LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apk add --no-cache build-base git postgresql-dev yaml-dev pkgconf

# Install application gems
COPY vendor/javascript ./vendor/javascript
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

ARG SCREENOTE_IMAGE_SOURCE="https://github.com/ivankuznetsov/screenote"
ARG SCREENOTE_IMAGE_REVISION="development"
ARG SCREENOTE_IMAGE_VERSION="development"
ARG SCREENOTE_IMAGE_DESCRIPTION="Screenote self-hosted visual review server"
LABEL org.opencontainers.image.source="$SCREENOTE_IMAGE_SOURCE" \
      org.opencontainers.image.revision="$SCREENOTE_IMAGE_REVISION" \
      org.opencontainers.image.version="$SCREENOTE_IMAGE_VERSION" \
      org.opencontainers.image.description="$SCREENOTE_IMAGE_DESCRIPTION" \
      org.opencontainers.image.licenses="LicenseRef-OSaasy"

# Run and own only the runtime files as a non-root user for security
RUN addgroup -S -g 1000 rails && \
    adduser -S -D -u 1000 -G rails -h /home/rails -s /bin/bash rails
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
