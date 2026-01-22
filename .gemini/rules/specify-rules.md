# freeswitch-arm Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-01-22

## Active Technologies
- N/A (Docker container ephemeral filesystem + Volumes) (001-arm-docker-wrapper)
- Bash (entrypoint script), XML (FreeSWITCH configuration) + `sed` (standard Unix utility for stream editing), Docker (002-xml-curl-env)
- N/A (Ephemeral container configuration) (002-xml-curl-env)
- Dockerfile syntax + Docker (003-copy-custom-config)
- File system (Docker image layer) (003-copy-custom-config)

- Dockerfile, Shell (Bash) + `signalwire/freeswitch` (Git), `signalwire/libks`, `signalwire/signalwire-c` (001-arm-docker-wrapper)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Dockerfile, Shell (Bash)

## Code Style

Dockerfile, Shell (Bash): Follow standard conventions

## Recent Changes
- 003-copy-custom-config: Added Dockerfile syntax + Docker
- 003-copy-custom-config: Added Dockerfile syntax + Docker
- 002-xml-curl-env: Added Bash (entrypoint script), XML (FreeSWITCH configuration) + `sed` (standard Unix utility for stream editing), Docker


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
