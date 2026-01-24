#!/bin/bash
# build-and-test.sh - Build FreeSWITCH-ARM image and run production readiness checkup
# 
# This script automates the build → deploy → test cycle:
#   1. Builds the Docker image
#   2. Starts a test container
#   3. Runs production readiness checks
#   4. Reports results
#
# Usage:
#   ./build-and-test.sh                      # Full build + test
#   ./build-and-test.sh --skip-build         # Test existing image
#   ./build-and-test.sh --backend-url URL    # Test with real backend

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
# Configuration
# =============================================================================

IMAGE_NAME="${IMAGE_NAME:-freeswitch-arm:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-freeswitch-checkup-$$}"
BACKEND_URL="${BACKEND_URL:-}"
SKIP_BUILD="${SKIP_BUILD:-false}"
CLEANUP="${CLEANUP:-true}"
VERBOSE="${VERBOSE:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       FreeSWITCH-ARM Build & Production Readiness Test       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
FreeSWITCH-ARM Build & Test Script

Usage: $(basename "$0") [OPTIONS]

This script builds the Docker image and runs production readiness checks.

OPTIONS:
    --image NAME         Image name (default: freeswitch-arm:latest)
    --container NAME     Container name for testing (default: auto-generated)
    --backend-url URL    Backend URL for integration tests
    --skip-build         Skip Docker build, use existing image
    --no-cleanup         Don't remove test container after tests
    --verbose, -v        Verbose output
    --help, -h           Show this help

EXAMPLES:
    # Build and test everything
    $(basename "$0")

    # Test existing image with real backend
    $(basename "$0") --skip-build --backend-url http://backend:3000

    # Build and test, keep container for debugging
    $(basename "$0") --no-cleanup

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --backend-url)
                BACKEND_URL="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        log_info "Cleaning up test container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    else
        log_warn "Container '$CONTAINER_NAME' left running for debugging"
        log_warn "  To view logs: docker logs $CONTAINER_NAME"
        log_warn "  To cleanup:   docker rm -f $CONTAINER_NAME"
    fi
}

trap cleanup EXIT

# =============================================================================
# Build
# =============================================================================

build_image() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping build (--skip-build)"
        return 0
    fi

    log_info "Building Docker image: $IMAGE_NAME"
    
    local start_time
    start_time=$(date +%s)
    
    if docker build -t "$IMAGE_NAME" "$PROJECT_ROOT"; then
        local elapsed=$(($(date +%s) - start_time))
        log_success "Build completed in ${elapsed}s"
        return 0
    else
        log_error "Build failed!"
        return 1
    fi
}

# =============================================================================
# Start Container
# =============================================================================

start_container() {
    log_info "Starting test container: $CONTAINER_NAME"
    
    local env_args=()
    
    if [[ -n "$BACKEND_URL" ]]; then
        env_args+=("-e" "XML_CURL_URL=${BACKEND_URL}/freeswitch/xml")
    fi
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --ulimit nofile=65535:65535 \
        --ulimit core=-1 \
        "${env_args[@]}" \
        "$IMAGE_NAME" || return 1
    
    log_info "Waiting for container to become healthy..."
    
    local timeout=90
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "healthy" ]]; then
            log_success "Container is healthy (${elapsed}s)"
            return 0
        fi
        
        sleep 2
        ((elapsed+=2))
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo -n "."
        fi
    done
    
    log_error "Container did not become healthy within ${timeout}s"
    log_error "Current status: $(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)"
    docker logs "$CONTAINER_NAME" --tail 20
    return 1
}

# =============================================================================
# Run Checkup
# =============================================================================

run_checkup() {
    log_info "Running production readiness checkup..."
    
    local checkup_dir="$PROJECT_ROOT/scripts/checkup"
    
    if [[ ! -d "$checkup_dir" ]]; then
        log_error "Checkup scripts not found: $checkup_dir"
        return 1
    fi
    
    # Build arguments
    local args=()
    args+=("--container" "$CONTAINER_NAME")
    args+=("--image" "$IMAGE_NAME")
    args+=("--skip-build")  # Already built
    
    if [[ -n "$BACKEND_URL" ]]; then
        args+=("--backend-url" "$BACKEND_URL")
    else
        # Skip integration tests if no backend
        args+=("--category" "docker")
        args+=("--category" "telephony")
        args+=("--category" "performance")
        args+=("--category" "security")
        log_warn "No --backend-url specified, skipping integration tests"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        args+=("--verbose")
    fi
    
    # Run checkup
    if bash "$checkup_dir/run-all.sh" "${args[@]}"; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    print_banner
    
    log_info "Image: $IMAGE_NAME"
    log_info "Container: $CONTAINER_NAME"
    log_info "Backend: ${BACKEND_URL:-<not set>}"
    log_info "Skip Build: $SKIP_BUILD"
    echo ""
    
    # Step 1: Build
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 1/3: Build"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ! build_image; then
        log_error "Build failed - aborting"
        exit 1
    fi
    echo ""
    
    # Step 2: Start Container
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 2/3: Start Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ! start_container; then
        log_error "Container startup failed - aborting"
        exit 1
    fi
    echo ""
    
    # Step 3: Run Checkup
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 3/3: Production Readiness Checkup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if run_checkup; then
        echo ""
        log_success "✅ Build and test completed successfully!"
        log_success "   Image '$IMAGE_NAME' is production ready."
        exit 0
    else
        echo ""
        log_error "❌ Production readiness checks failed!"
        log_error "   Review the output above for details."
        exit 1
    fi
}

main "$@"
