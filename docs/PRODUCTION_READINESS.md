# FreeSWITCH-ARM Production Readiness Checkup

This document describes the production readiness validation suite for the FreeSWITCH-ARM Docker container.

## Overview

The Production Readiness Checkup validates that the `freeswitch-arm` container is ready for deployment in a production environment. It performs automated checks across five categories:

| Category | Priority | Description |
|----------|----------|-------------|
| **Docker** | P1 | Image build, architecture, healthcheck, volumes |
| **Integration** | P1 | xml_curl communication with backend |
| **Telephony** | P2 | SIP registration, codecs, calling |
| **Performance** | P2 | Ulimits, logs, restart behavior |
| **Security** | P3 | Non-root user, ports, file permissions |

## Quick Start

```bash
# 1. Ensure FreeSWITCH container is running
docker ps | grep freeswitch

# 2. Run all checks
./scripts/checkup/run-all.sh --backend-url http://backend:3000

# 3. View results
# ✅ PRODUCTION READY or ❌ NOT PRODUCTION READY
```

## Installation

The checkup scripts are included in the `freeswitch-arm` repository:

```bash
# Clone repository
git clone https://github.com/your-org/freeswitch-arm.git
cd freeswitch-arm

# Make scripts executable
chmod +x scripts/checkup/*.sh
chmod +x scripts/checkup/lib/*.sh
```

## Usage

### Run All Categories

```bash
./scripts/checkup/run-all.sh --backend-url http://backend:3000
```

### Run Specific Categories

```bash
# Only P1 (critical) checks
./scripts/checkup/run-all.sh --backend-url http://backend:3000 \
    --category docker --category integration

# Only Docker validation
./scripts/checkup/run-all.sh --category docker --skip-build
```

### Run Individual Scripts

```bash
# Docker validation
./scripts/checkup/01-docker-validation.sh --skip-build

# Integration with backend
./scripts/checkup/02-integration.sh --backend-url http://backend:3000

# Telephony
./scripts/checkup/03-telephony.sh

# Performance
./scripts/checkup/04-performance.sh

# Security
./scripts/checkup/05-security.sh
```

### Options

| Option | Description |
|--------|-------------|
| `--backend-url URL` | Backend API URL (required for integration) |
| `--container NAME` | Container name (default: freeswitch) |
| `--image NAME` | Image name (default: freeswitch-arm:latest) |
| `--skip-build` | Skip build validation |
| `--category CAT` | Run only specific category |
| `--json` | Output as JSON |
| `--verbose` | Verbose output |

## Output Formats

### Console Output

```
╔════════════════════════════════════════════════════════════════╗
║        FreeSWITCH-ARM Production Readiness Checkup             ║
╠════════════════════════════════════════════════════════════════╣
║ Host: prod-server-01             Arch: aarch64                 ║
╠════════════════════════════════════════════════════════════════╣
║ [P1] Docker Validation          ✅ PASSED (5/5)                ║
║ [P1] Integration                ✅ PASSED (5/5)                ║
║ [P2] Telephony                  ✅ PASSED (4/4)                ║
║ [P2] Performance                ✅ PASSED (6/6)                ║
║ [P3] Security                   ✅ PASSED (5/5)                ║
╠════════════════════════════════════════════════════════════════╣
║ Total: 25/25                    Duration: 2m 45s               ║
║ Status: ✅ PRODUCTION READY                                    ║
╚════════════════════════════════════════════════════════════════╝
```

### JSON Output

```bash
./scripts/checkup/run-all.sh --backend-url http://backend:3000 --json
```

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-01-24T10:30:00Z",
  "summary": {
    "total_checks": 25,
    "passed": 25,
    "failed": 0,
    "pass_rate": 100,
    "production_ready": true
  },
  "duration_seconds": 165
}
```

## Local Testing Environment

For testing without a production backend:

```bash
# Start local test environment
docker compose -f infrastructure/docker-compose.checkup.yml up -d

# Wait for services to be healthy
docker compose -f infrastructure/docker-compose.checkup.yml ps

# Run checkup
./scripts/checkup/run-all.sh --backend-url http://localhost:3000

# Cleanup
docker compose -f infrastructure/docker-compose.checkup.yml down -v
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Production Readiness Check

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  checkup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Build FreeSWITCH Image
        run: docker build -t freeswitch-arm:latest .
      
      - name: Start Test Environment
        run: docker compose -f infrastructure/docker-compose.checkup.yml up -d
      
      - name: Wait for Healthy
        run: |
          timeout 120 bash -c 'until docker inspect freeswitch-checkup --format="{{.State.Health.Status}}" | grep -q healthy; do sleep 5; done'
      
      - name: Run Production Readiness Checkup
        run: |
          ./scripts/checkup/run-all.sh \
            --backend-url http://localhost:3000 \
            --json > checkup-report.json
      
      - name: Upload Report
        uses: actions/upload-artifact@v4
        with:
          name: checkup-report
          path: checkup-report.json
      
      - name: Verify Production Ready
        run: |
          if jq -e '.summary.production_ready == false' checkup-report.json > /dev/null; then
            echo "❌ Not production ready"
            jq '.summary' checkup-report.json
            exit 1
          fi
          echo "✅ Production ready"
```

## Checks Reference

### Docker Validation (P1)

| Check | Requirement | Description |
|-------|-------------|-------------|
| docker-001 | FR-001 | Build completes successfully |
| docker-002 | FR-001 | Image architecture is arm64 |
| docker-003 | FR-006 | Healthcheck is configured |
| docker-004 | FR-006 | Container reaches healthy status |
| docker-005 | FR-009 | Volumes are configured |

### Integration (P1)

| Check | Requirement | Description |
|-------|-------------|-------------|
| int-001 | FR-002 | mod_xml_curl module is loaded |
| int-002 | FR-003 | XML_CURL_URL is configured |
| int-003 | FR-010 | Configuration request works |
| int-004 | FR-010 | Directory request works |
| int-005 | FR-010 | Dialplan request works |

### Telephony (P2)

| Check | Requirement | Description |
|-------|-------------|-------------|
| tel-001 | FR-007 | mod_sofia is loaded |
| tel-002 | FR-004 | SIP port is listening |
| tel-003 | FR-008 | Required codecs available |
| tel-004 | - | SIP registration works |

### Performance (P2)

| Check | Requirement | Description |
|-------|-------------|-------------|
| perf-001 | - | Ulimits >= 65535 |
| perf-002 | - | No critical errors in logs |
| perf-003 | - | Graceful restart < 30s |
| perf-004 | - | Startup time < 90s |
| perf-005 | - | Memory usage < 80% |
| perf-006 | - | Core dump enabled |

### Security (P3)

| Check | Requirement | Description |
|-------|-------------|-------------|
| sec-001 | FR-005 | Process runs as non-root |
| sec-002 | FR-004 | Only required ports exposed |
| sec-003 | - | Sensitive files protected |
| sec-004 | - | No default passwords |
| sec-005 | - | Event socket protected |

## Troubleshooting

### Check Failed: Container Not Found

```bash
# Verify container is running
docker ps

# Start container if needed
docker start freeswitch
```

### Check Failed: Backend Not Accessible

```bash
# Test connectivity
curl -I http://backend:3000/health

# Check network
docker network inspect bridge
```

### Check Failed: mod_xml_curl Not Loaded

```bash
# Check loaded modules
docker exec freeswitch fs_cli -x "show modules" | grep xml_curl

# Reload module
docker exec freeswitch fs_cli -x "load mod_xml_curl"
```

## See Also

- [Specification](../specs/001-production-readiness/spec.md)
- [Implementation Plan](../specs/001-production-readiness/plan.md)
- [Quick Start Guide](../specs/001-production-readiness/quickstart.md)
