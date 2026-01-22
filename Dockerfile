FROM debian:bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    automake \
    autoconf \
    libtool \
    libtool-bin \
    pkg-config \
    git \
    wget \
    curl \
    libssl-dev \
    libncurses5-dev \
    libjpeg-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libpcre2-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libldns-dev \
    libedit-dev \
    libopus-dev \
    libsndfile1-dev \
    yasm \
    nasm \
    liblua5.3-dev \
    uuid-dev \
    zlib1g-dev \
    libpq-dev \
    libtiff-dev \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /usr/src

# Build libks
RUN git clone https://github.com/signalwire/libks.git \
    && cd libks \
    && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=OFF \
    && make -j$(nproc) \

# Build signalwire-c
RUN git clone https://github.com/signalwire/signalwire-c.git \
    && cd signalwire-c \
    && cmake . -DCMAKE_INSTALL_PREFIX=/usr \
    && make -j$(nproc) \

# Build FreeSWITCH
# Using a specific tag/commit can be safer, but master is requested for "wrapper of freeswitch-arm repo" 
# (assuming latest source). You might want to pin a version if stability is key.
RUN git clone https://github.com/signalwire/freeswitch.git \
    && cd freeswitch \
    && ./bootstrap.sh -j


# Configure and Build
# Disable zrtp to avoid dependency complexity if not needed, or ensure libzrtp is present.
# We stick to standard build.
RUN cd freeswitch \
    && ./configure --prefix=/usr/local/freeswitch \
    && make -j$(nproc) \

# -----------------------------------------------------------------------------
# Stage 2: Runtime
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies (must match what was linked against in build)
# libks/signalwire-c might install libs to /usr/lib or /usr/local/lib.
# We verify specific libs after build or generically include common runtimes.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libncurses5 \
    libjpeg62-turbo \
    libsqlite3-0 \
    libcurl4 \
    libpcre2-8-0 \
    libspeex1 \
    libspeexdsp1 \
    libldns3 \
    libedit2 \
    libopus0 \
    libsndfile1 \
    liblua5.3-0 \
    libuuid1 \
    zlib1g \
    libpq5 \
    libtiff6 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy built artifacts from build stage
COPY --from=build /usr/local/freeswitch /usr/local/freeswitch
COPY --from=build /usr/lib/*signalwire* /usr/lib/
COPY --from=build /usr/lib/*libks* /usr/lib/
# Also check /usr/local/lib for signalwire/ks if cmake installed there
COPY --from=build /usr/local/lib/*signalwire* /usr/local/lib/ || true
COPY --from=build /usr/local/lib/*libks* /usr/local/lib/ || true
COPY --from=build /usr/include/*signalwire* /usr/include/ || true
COPY --from=build /usr/include/*libks* /usr/include/ || true

# Refresh ld cache
RUN ldconfig

# Create user/group (optional, but good practice. Spec didn't strictly mandate rootless, but implicit in US2 config)
RUN groupadd -r freeswitch && useradd -r -g freeswitch freeswitch

# Permissions
RUN chown -R freeswitch:freeswitch /usr/local/freeswitch

ENV PATH="/usr/local/freeswitch/bin:$PATH"


# Install gosu for easy step-down from root
RUN set -eux; \
    apt-get update; \
    apt-get install -y gosu; \
    rm -rf /var/lib/apt/lists/*; \
    gosu nobody true

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Ports for SIP (5060/5061/5080/5081) and RTP (16384-32768) and ESL (8021)
EXPOSE 5060/tcp 5060/udp 5080/tcp 5080/udp
EXPOSE 5061/tcp 5061/udp 5081/tcp 5081/udp
EXPOSE 8021/tcp
EXPOSE 16384-32768/udp

# Volumes
VOLUME ["/usr/local/freeswitch/conf", "/usr/local/freeswitch/log", "/usr/local/freeswitch/run", "/usr/local/freeswitch/db"]

# Healthcheck
HEALTHCHECK --interval=15s --timeout=5s \
    CMD /usr/local/freeswitch/bin/fs_cli -x status | grep -q ^UP || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["freeswitch"]






