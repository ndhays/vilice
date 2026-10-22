# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Build it with `make image`
# from the repo root, which passes the two build contexts it needs (Boxcar and VERSION):
# docker build --build-context boxcar=../../boxcar-rails --build-context repo=.. -t vilice-console .
# docker run -d -p 80:80 -e SECRET_KEY_BASE=… -e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=… \
#   -e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=… -e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=… \
#   --name vilice-console vilice-console

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
# openssh-client: the console reaches every box over scoped SSH (app/services/vilice.rb).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips openssh-client sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems. Boxcar is a path gem in a sibling checkout (../../boxcar-rails
# from here), and the version is the repo root's VERSION — both outside this folder, so
# both arrive as named build contexts (`make image`, which passes them). /rails/../..
# is /, so the Gemfile's relative path finds Boxcar at /boxcar-rails.
COPY --from=boxcar . /boxcar-rails/
COPY --from=repo VERSION /VERSION
COPY vendor/* ./vendor/
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

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
# Bundler loads a path gem from its path at runtime, and the app reads VERSION at boot.
COPY --chown=rails:rails --from=build /boxcar-rails /boxcar-rails
COPY --chown=rails:rails --from=build /VERSION /VERSION

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
