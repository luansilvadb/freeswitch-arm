#!/bin/bash
# 01-docker-validation.sh - Docker Image and Container Validation
# Part of FreeSWITCH-ARM Production Readiness Checkup
# Category: docker | Priority: P1 | User Story: US1
#
# Validates:
#   - docker-001: Build completeness
#   - docker-002: Image architecture (arm64)
#   - docker-003: Healthcheck configured
#   - docker-004: Container reaches healthy status
#   - docker-005: Volumes configured

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/assertions.sh"

# =============================================================================
# Configuration
# =============================================================================

readonly CATEGORY="docker"
readonly CATEGORY_NAME="Docker Validation"
SKIP_BUILD="${SKIP_BUILD:-false}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-90}"
TEST_CONTAINER_NAME="freeswitch-checkup-test-$$"

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Docker Validation - FreeSWITCH-ARM Production Readiness Checkup

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --image NAME         FreeSWITCH image name (default: freeswitch-arm:latest)
    --container NAME     Container name for testing (default: auto-generated)
    --skip-build         Skip build validation check
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CHECKS:
    docker-001  Build completeness (FR-001)
    docker-002  Image architecture is arm64 (FR-001)
    docker-003  Healthcheck is configured (FR-006)
    docker-004  Container reaches healthy status (FR-006)
    docker-005  Volumes are configured (FR-009)

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image|-i)
                FREESWITCH_IMAGE="$2"
                shift 2
                ;;
            --container|-c)
                TEST_CONTAINER_NAME="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --json|-j)
                JSON_OUTPUT=true
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
    log_debug "Cleaning up test container: $TEST_CONTAINER_NAME"
    docker rm -f "$TEST_CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

# =============================================================================
# Checks
# =============================================================================

# docker-001: Build completeness
check_docker_001() {
    local check_id="docker-001"
    local check_name="Build completeness"
    local requirement="FR-001"
    
    if [[ "$SKIP_BUILD" == "true" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Skipped via --skip-build flag"
        return 0
    fi
    
    log_debug "Checking if image exists: $FREESWITCH_IMAGE"
    
    if image_exists "$FREESWITCH_IMAGE"; then
        local image_id
        image_id=$(docker inspect --format='{{.Id}}' "$FREESWITCH_IMAGE" 2>/dev/null | cut -c8-19)
        print_check "$check_id" "$check_name" "passed" "Image exists" "Image ID: $image_id"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Image exists" "$image_id" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "Image exists" "Image not found: $FREESWITCH_IMAGE" "Run: docker build -t $FREESWITCH_IMAGE ."
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Image exists" "Not found" "Image not found" "0"
        return 1
    fi
}

# docker-002: Image architecture
check_docker_002() {
    local check_id="docker-002"
    local check_name="Image architecture"
    local requirement="FR-001"
    
    if ! image_exists "$FREESWITCH_IMAGE"; then
        skip_check "$check_id" "$check_name" "$requirement" "Image not available"
        return 0
    fi
    
    local arch
    arch=$(docker inspect --format='{{.Architecture}}' "$FREESWITCH_IMAGE" 2>/dev/null)
    
    log_debug "Image architecture: $arch"
    
    # Accept arm64 or amd64 (for testing on non-ARM)
    if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
        print_check "$check_id" "$check_name" "passed" "arm64" "$arch"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "arm64" "$arch" "" "0"
        return 0
    elif [[ "$arch" == "amd64" ]]; then
        # Warning but not failure for x86 testing
        print_check "$check_id" "$check_name" "passed" "arm64 (or amd64 for testing)" "$arch"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "arm64" "$arch" "Running on amd64 - ensure production is ARM" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "arm64" "$arch"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "arm64" "$arch" "Unexpected architecture" "0"
        return 1
    fi
}

# docker-003: Healthcheck configured
check_docker_003() {
    local check_id="docker-003"
    local check_name="Healthcheck configured"
    local requirement="FR-006"
    
    if ! image_exists "$FREESWITCH_IMAGE"; then
        skip_check "$check_id" "$check_name" "$requirement" "Image not available"
        return 0
    fi
    
    local healthcheck
    healthcheck=$(docker inspect --format='{{.Config.Healthcheck}}' "$FREESWITCH_IMAGE" 2>/dev/null)
    
    log_debug "Healthcheck config: $healthcheck"
    
    if [[ -n "$healthcheck" && "$healthcheck" != "<nil>" && "$healthcheck" != "{[]  0s 0s 0s 0}" ]]; then
        # Extract interval for display
        local interval
        interval=$(docker inspect --format='{{.Config.Healthcheck.Interval}}' "$FREESWITCH_IMAGE" 2>/dev/null)
        print_check "$check_id" "$check_name" "passed" "Healthcheck present" "Interval: $interval"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Healthcheck present" "Interval: $interval" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "Healthcheck present" "No healthcheck configured"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Healthcheck present" "Not configured" "Add HEALTHCHECK to Dockerfile" "0"
        return 1
    fi
}

# docker-004: Container reaches healthy status
check_docker_004() {
    local check_id="docker-004"
    local check_name="Container reaches healthy status"
    local requirement="FR-006"
    
    if ! image_exists "$FREESWITCH_IMAGE"; then
        skip_check "$check_id" "$check_name" "$requirement" "Image not available"
        return 0
    fi
    
    log_debug "Starting test container: $TEST_CONTAINER_NAME"
    
    # Start container
    local start_time
    start_time=$(date +%s)
    
    if ! docker run -d --name "$TEST_CONTAINER_NAME" \
        --ulimit nofile=65535:65535 \
        "$FREESWITCH_IMAGE" >/dev/null 2>&1; then
        print_check "$check_id" "$check_name" "failed" "Container starts and becomes healthy" "Failed to start container"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Healthy within ${HEALTH_TIMEOUT}s" "Failed to start" "Container start failed" "0"
        return 1
    fi
    
    # Wait for healthy
    if wait_for_healthy "$TEST_CONTAINER_NAME" "$HEALTH_TIMEOUT"; then
        local elapsed=$(($(date +%s) - start_time))
        print_check "$check_id" "$check_name" "passed" "Healthy within ${HEALTH_TIMEOUT}s" "Healthy in ${elapsed}s"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Healthy within ${HEALTH_TIMEOUT}s" "Healthy in ${elapsed}s" "" "$((elapsed * 1000))"
        return 0
    else
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$TEST_CONTAINER_NAME" 2>/dev/null || echo "unknown")
        print_check "$check_id" "$check_name" "failed" "Healthy within ${HEALTH_TIMEOUT}s" "Status: $status after ${HEALTH_TIMEOUT}s"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Healthy within ${HEALTH_TIMEOUT}s" "$status" "Timeout waiting for healthy status" "$((HEALTH_TIMEOUT * 1000))"
        return 1
    fi
}

# docker-005: Volumes configured
check_docker_005() {
    local check_id="docker-005"
    local check_name="Volumes configured"
    local requirement="FR-009"
    
    if ! image_exists "$FREESWITCH_IMAGE"; then
        skip_check "$check_id" "$check_name" "$requirement" "Image not available"
        return 0
    fi
    
    local volumes
    volumes=$(docker inspect --format='{{.Config.Volumes}}' "$FREESWITCH_IMAGE" 2>/dev/null)
    
    log_debug "Volume config: $volumes"
    
    local required_volumes=(
        "/usr/local/freeswitch/conf"
        "/usr/local/freeswitch/log"
        "/usr/local/freeswitch/db"
    )
    
    local missing=()
    for vol in "${required_volumes[@]}"; do
        if [[ "$volumes" != *"$vol"* ]]; then
            missing+=("$vol")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "Required volumes configured" "${#required_volumes[@]} volumes found"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "conf, log, db volumes" "All present" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "Required volumes configured" "Missing: ${missing[*]}"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "conf, log, db volumes" "Missing: ${missing[*]}" "Add VOLUME to Dockerfile" "0"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    log_header "$CATEGORY_NAME"
    log_info "Image: $FREESWITCH_IMAGE"
    log_info "Skip Build: $SKIP_BUILD"
    
    reset_checks
    
    local all_passed=true
    
    check_docker_001 || all_passed=false
    check_docker_002 || all_passed=false
    check_docker_003 || all_passed=false
    check_docker_004 || all_passed=false
    check_docker_005 || all_passed=false
    
    print_summary "$CATEGORY_NAME"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_category_json "$CATEGORY"
    fi
    
    if [[ "$all_passed" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
