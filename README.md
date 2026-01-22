# Oracle Cloud ARM64 FreeSWITCH Wrapper

This repository contains a Docker-based FreeSWITCH wrapper optimized for ARM64 architectures, specifically targeted at Oracle Cloud Ampere A1 instances.

It builds FreeSWITCH from source to ensure full compatibility with the `aarch64` processor architecture, which standard Debian packages may not fully support.

## Key Features

*   **Multi-stage Build**: Compiles from source but delivers a lightweight runtime image.
*   **ARM64 Optimized**: Specifically targeting `linux/arm64`.
*   **Module Safety**: Explicitly disables `mod_v8` to prevent known ARM build failures.
*   **Production Ready**: Includes `entrypoint.sh` for process management and correct signal handling.

## Usage

### 1. Build the Image

On your ARM64 instance:

```bash
docker build -t freeswitch-arm .
```

*Note: The build process compiles FreeSWITCH, libks, and signalwire-c from source. Expect this to take 20-45 minutes depending on your instance size.*

### 2. Run FreeSWITCH

For VoIP applications, **host networking** is strongly recommended to simplify RTP port management:

```bash
docker run -d \
  --name freeswitch \
  --net=host \
  --restart always \
  --ulimit nofile=65535:65535 \
  --ulimit core=-1 \
  -v freeswitch-conf:/usr/local/freeswitch/conf \
  -v freeswitch-log:/usr/local/freeswitch/log \
  -v freeswitch-db:/usr/local/freeswitch/db \
  freeswitch-arm
```

If you prefer bridge networking, you must map all ports:

```bash
docker run -d \
  --name freeswitch \
  -p 5060:5060/tcp -p 5060:5060/udp \
  -p 5080:5080/tcp -p 5080:5080/udp \
  -p 5061:5061/tcp -p 5061:5061/udp \
  -p 8021:8021/tcp \
  -p 16384-32768:16384-32768/udp \
  freeswitch-arm
```

### 3. Configuration

To edit configuration, access the volume or mount a local directory:

```bash
# Copy default config out first
docker run --rm freeswitch-arm cp -r /usr/local/freeswitch/conf /tmp/my-conf

# Run with local config
docker run -d ... -v /tmp/my-conf:/usr/local/freeswitch/conf ...
```

## Troubleshooting

*   **Memory Issues**: If the build fails with random errors, you may be running out of RAM (especially on 1GB instances). Ensure you have at least 4GB RAM or add swap.
*   **SIP Connectivity**: Check your Oracle Cloud Security List to allow ingress UDP/TCP 5060 and UDP 16384-32768.
