#!/bin/bash
# common.sh - Shared functions for checkup scripts
# Part of FreeSWITCH-ARM Production Readiness Checkup

# Source colors (relative to this script's location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/colors.sh"

# Global variables
VERBOSE=${VERBOSE:-false}
JSON_OUTPUT=${JSON_OUTPUT:-false}
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0
CHECKS_TOTAL=0

# Container defaults
FREESWITCH_CONTAINER=${FREESWITCH_CONTAINER:-freeswitch}
FREESWITCH_IMAGE=${FREESWITCH_IMAGE:-freeswitch-arm:latest}

# Logging functions
log_info() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $*"
    fi
}

log_error() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

log_warn() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*"
    fi
}

log_debug() {
    if [[ "$VERBOSE" == "true" && "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${DIM}[DEBUG]${NC} $*"
    fi
}

log_header() {
    local title="$1"
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}[$title]${NC} Starting validation..."
    fi
}

# Check result formatting
print_check() {
    local check_id="$1"
    local check_name="$2"
    local status="$3"      # passed, failed, skipped
    local expected="$4"
    local actual="$5"
    local message="${6:-}"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return
    fi

    echo ""
    echo -e "${BOLD}[CHECK]${NC} ${check_id}: ${check_name}"
    echo -e "  ├─ Expected: ${expected}"
    echo -e "  ├─ Actual: ${actual}"
    
    case "$status" in
        passed)
            echo -e "  └─ Status: $(status_pass)"
            ((CHECKS_PASSED++))
            ;;
        failed)
            echo -e "  └─ Status: $(status_fail)"
            if [[ -n "$message" ]]; then
                echo -e "     ${RED}${message}${NC}"
            fi
            ((CHECKS_FAILED++))
            ;;
        skipped)
            echo -e "  └─ Status: $(status_skip)"
            if [[ -n "$message" ]]; then
                echo -e "     ${DIM}${message}${NC}"
            fi
            ((CHECKS_SKIPPED++))
            ;;
    esac
    ((CHECKS_TOTAL++))
}

# Summary output
print_summary() {
    local category="$1"
    local status
    
    if [[ "$CHECKS_FAILED" -eq 0 ]]; then
        status="${GREEN}PASSED${NC}"
    else
        status="${RED}FAILED${NC}"
    fi

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        echo -e "${BOLD}[$category]${NC} Result: ${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed ${status}"
    fi
}

# Docker helper functions
container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${1}$"
}

container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${1}$"
}

container_healthy() {
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$1" 2>/dev/null)
    [[ "$status" == "healthy" ]]
}

image_exists() {
    docker image inspect "$1" &>/dev/null
}

# Execute command in container
exec_in_container() {
    local container="$1"
    shift
    docker exec "$container" "$@"
}

# Wait for container to be healthy
wait_for_healthy() {
    local container="$1"
    local timeout="${2:-90}"
    local elapsed=0
    
    log_debug "Waiting for container '$container' to be healthy (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        if container_healthy "$container"; then
            log_debug "Container healthy after ${elapsed}s"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done
    
    log_debug "Timeout waiting for container to be healthy"
    return 1
}

# Parse common arguments
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --json|-j)
                JSON_OUTPUT=true
                shift
                ;;
            --container|-c)
                FREESWITCH_CONTAINER="$2"
                shift 2
                ;;
            --image|-i)
                FREESWITCH_IMAGE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # Unknown argument, let caller handle
                break
                ;;
        esac
    done
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$-$RANDOM"
    fi
}

# Get current timestamp in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Calculate duration
get_duration() {
    local start_time="$1"
    local end_time="${2:-$(date +%s)}"
    echo $((end_time - start_time))
}
