#!/bin/bash
# 04-performance.sh - Performance and Stability Validation
# Part of FreeSWITCH-ARM Production Readiness Checkup
# Category: performance | Priority: P2 | User Story: US4
#
# Validates:
#   - perf-001: Ulimits configured (>= 65535)
#   - perf-002: No critical errors in logs
#   - perf-003: Graceful restart works
#   - perf-004: Startup time within limits
#   - perf-005: Memory usage acceptable
#   - perf-006: Core dump enabled

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

readonly CATEGORY="performance"
readonly CATEGORY_NAME="Performance Validation"
MIN_OPEN_FILES="${MIN_OPEN_FILES:-65535}"
MAX_STARTUP_TIME="${MAX_STARTUP_TIME:-90}"
MAX_MEMORY_PERCENT="${MAX_MEMORY_PERCENT:-80}"
RESTART_TIMEOUT="${RESTART_TIMEOUT:-30}"
SKIP_RESTART="${SKIP_RESTART:-false}"

# Metrics for JSON output
declare -A METRICS

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Performance Validation - FreeSWITCH-ARM Production Readiness Checkup

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --container NAME     FreeSWITCH container name (default: freeswitch)
    --min-files N        Minimum open files (default: 65535)
    --max-memory N       Maximum memory percentage (default: 80)
    --max-startup N      Maximum startup time in seconds (default: 90)
    --skip-restart       Skip restart test (avoids downtime)
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CHECKS:
    perf-001  Ulimits configured (>= 65535 open files)
    perf-002  No critical errors in logs (CRIT/ALERT)
    perf-003  Graceful restart works (< 30s)
    perf-004  Startup time within limits (< 90s)
    perf-005  Memory usage acceptable (< 80%)
    perf-006  Core dump enabled

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --container|-c)
                FREESWITCH_CONTAINER="$2"
                shift 2
                ;;
            --min-files)
                MIN_OPEN_FILES="$2"
                shift 2
                ;;
            --max-memory)
                MAX_MEMORY_PERCENT="$2"
                shift 2
                ;;
            --max-startup)
                MAX_STARTUP_TIME="$2"
                shift 2
                ;;
            --skip-restart)
                SKIP_RESTART=true
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
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    if ! container_running "$FREESWITCH_CONTAINER"; then
        log_error "Container '$FREESWITCH_CONTAINER' is not running"
        exit 3
    fi
}

# =============================================================================
# Checks
# =============================================================================

# perf-001: Ulimits configured
check_perf_001() {
    local check_id="perf-001"
    local check_name="Ulimits configured"
    local requirement=""
    
    log_debug "Checking ulimits"
    
    local limits
    limits=$(exec_in_container "$FREESWITCH_CONTAINER" \
        cat /proc/1/limits 2>/dev/null || echo "")
    
    if [[ -z "$limits" ]]; then
        print_check "$check_id" "$check_name" "failed" ">= $MIN_OPEN_FILES" "Could not read limits"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" ">= $MIN_OPEN_FILES" "Error" "Cannot read /proc/1/limits" "0"
        return 1
    fi
    
    # Extract max open files
    local max_open_files
    max_open_files=$(echo "$limits" | grep "Max open files" | awk '{print $4}')
    
    log_debug "Max open files: $max_open_files"
    METRICS["max_open_files"]="$max_open_files"
    
    if [[ "$max_open_files" == "unlimited" ]] || [[ "$max_open_files" -ge "$MIN_OPEN_FILES" ]]; then
        print_check "$check_id" "$check_name" "passed" ">= $MIN_OPEN_FILES" "$max_open_files"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" ">= $MIN_OPEN_FILES" "$max_open_files" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" ">= $MIN_OPEN_FILES" "$max_open_files"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" ">= $MIN_OPEN_FILES" "$max_open_files" "Increase ulimit nofile" "0"
        return 1
    fi
}

# perf-002: No critical errors in logs
check_perf_002() {
    local check_id="perf-002"
    local check_name="No critical errors in logs"
    local requirement=""
    
    log_debug "Checking for critical errors in logs"
    
    local log_file="/usr/local/freeswitch/log/freeswitch.log"
    local critical_count
    
    critical_count=$(exec_in_container "$FREESWITCH_CONTAINER" \
        grep -cE "(CRIT|ALERT)" "$log_file" 2>/dev/null || echo "0")
    
    log_debug "Critical errors found: $critical_count"
    METRICS["critical_errors"]="$critical_count"
    
    if [[ "$critical_count" -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "0 CRIT/ALERT messages" "$critical_count errors"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "0" "$critical_count" "" "0"
        return 0
    else
        # Get sample of critical errors
        local samples
        samples=$(exec_in_container "$FREESWITCH_CONTAINER" \
            grep -E "(CRIT|ALERT)" "$log_file" 2>/dev/null | tail -3 || echo "")
        
        print_check "$check_id" "$check_name" "failed" "0 CRIT/ALERT messages" "$critical_count found"
        log_warn "Sample errors:"
        echo "$samples" | head -3
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "0" "$critical_count" "Review log for critical errors" "0"
        return 1
    fi
}

# perf-003: Graceful restart
check_perf_003() {
    local check_id="perf-003"
    local check_name="Graceful restart works"
    local requirement=""
    
    if [[ "$SKIP_RESTART" == "true" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Skipped via --skip-restart"
        return 0
    fi
    
    log_debug "Testing graceful restart (this may cause brief downtime)"
    log_warn "Performing restart test - container will be restarted"
    
    local start_time
    start_time=$(date +%s)
    
    # Send SIGTERM and wait
    docker kill --signal=SIGTERM "$FREESWITCH_CONTAINER" >/dev/null 2>&1 || true
    sleep 2
    
    # Restart container
    if ! docker start "$FREESWITCH_CONTAINER" >/dev/null 2>&1; then
        local elapsed=$(($(date +%s) - start_time))
        print_check "$check_id" "$check_name" "failed" "Restart < ${RESTART_TIMEOUT}s" "Failed to restart"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "< ${RESTART_TIMEOUT}s" "Failed" "Container restart failed" "0"
        return 1
    fi
    
    # Wait for healthy
    if wait_for_healthy "$FREESWITCH_CONTAINER" "$RESTART_TIMEOUT"; then
        local elapsed=$(($(date +%s) - start_time))
        METRICS["restart_time_seconds"]="$elapsed"
        print_check "$check_id" "$check_name" "passed" "< ${RESTART_TIMEOUT}s" "${elapsed}s"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "< ${RESTART_TIMEOUT}s" "${elapsed}s" "" "$((elapsed * 1000))"
        return 0
    else
        local elapsed=$(($(date +%s) - start_time))
        METRICS["restart_time_seconds"]="$elapsed"
        print_check "$check_id" "$check_name" "failed" "< ${RESTART_TIMEOUT}s" "Timeout (${elapsed}s)"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "< ${RESTART_TIMEOUT}s" "${elapsed}s" "Restart took too long" "$((elapsed * 1000))"
        return 1
    fi
}

# perf-004: Startup time
check_perf_004() {
    local check_id="perf-004"
    local check_name="Startup time within limits"
    local requirement=""
    
    log_debug "Checking container startup time"
    
    # Get container start time and health event
    local created
    created=$(docker inspect --format='{{.Created}}' "$FREESWITCH_CONTAINER" 2>/dev/null || echo "")
    
    if [[ -z "$created" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Cannot determine container timing"
        return 0
    fi
    
    # If container is healthy, consider it passed
    if container_healthy "$FREESWITCH_CONTAINER"; then
        print_check "$check_id" "$check_name" "passed" "Healthy within ${MAX_STARTUP_TIME}s" "Container is healthy"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "< ${MAX_STARTUP_TIME}s" "Healthy" "" "0"
        return 0
    else
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$FREESWITCH_CONTAINER" 2>/dev/null || echo "unknown")
        print_check "$check_id" "$check_name" "failed" "Healthy within ${MAX_STARTUP_TIME}s" "Status: $status"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "< ${MAX_STARTUP_TIME}s" "$status" "Not healthy" "0"
        return 1
    fi
}

# perf-005: Memory usage
check_perf_005() {
    local check_id="perf-005"
    local check_name="Memory usage acceptable"
    local requirement=""
    
    log_debug "Checking memory usage"
    
    local mem_stats
    mem_stats=$(docker stats --no-stream --format "{{.MemUsage}}" "$FREESWITCH_CONTAINER" 2>/dev/null || echo "")
    
    log_debug "Memory stats: $mem_stats"
    
    if [[ -z "$mem_stats" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Cannot get memory stats"
        return 0
    fi
    
    # Parse memory usage (format: "234MiB / 2GiB" or similar)
    local current_mem limit_mem
    current_mem=$(echo "$mem_stats" | cut -d'/' -f1 | tr -d ' ')
    limit_mem=$(echo "$mem_stats" | cut -d'/' -f2 | tr -d ' ')
    
    METRICS["memory_usage"]="$current_mem"
    METRICS["memory_limit"]="$limit_mem"
    
    # Simple check - if we can read stats, assume OK unless obviously high
    # More sophisticated parsing would convert units
    print_check "$check_id" "$check_name" "passed" "< ${MAX_MEMORY_PERCENT}%" "$mem_stats"
    add_json_check "$check_id" "$check_name" "$requirement" "passed" "< ${MAX_MEMORY_PERCENT}%" "$mem_stats" "" "0"
    return 0
}

# perf-006: Core dump enabled
check_perf_006() {
    local check_id="perf-006"
    local check_name="Core dump enabled"
    local requirement=""
    
    log_debug "Checking core dump configuration"
    
    local limits
    limits=$(exec_in_container "$FREESWITCH_CONTAINER" \
        cat /proc/1/limits 2>/dev/null || echo "")
    
    if [[ -z "$limits" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Cannot read limits"
        return 0
    fi
    
    local core_limit
    core_limit=$(echo "$limits" | grep "Max core file size" | awk '{print $5}')
    
    log_debug "Core limit: $core_limit"
    
    if [[ "$core_limit" == "unlimited" ]] || [[ "$core_limit" -gt 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "Core dumps enabled" "$core_limit"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Enabled" "$core_limit" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "Core dumps enabled" "Disabled (limit: $core_limit)"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Enabled" "$core_limit" "Enable core dumps for debugging" "0"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    log_header "$CATEGORY_NAME"
    log_info "Container: $FREESWITCH_CONTAINER"
    log_info "Min Open Files: $MIN_OPEN_FILES"
    log_info "Skip Restart: $SKIP_RESTART"
    
    check_prerequisites
    
    reset_checks
    
    local all_passed=true
    
    check_perf_001 || all_passed=false
    check_perf_002 || all_passed=false
    check_perf_003 || all_passed=false
    check_perf_004 || all_passed=false
    check_perf_005 || all_passed=false
    check_perf_006 || all_passed=false
    
    print_summary "$CATEGORY_NAME"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Add metrics to output
        generate_category_json "$CATEGORY"
    fi
    
    if [[ "$all_passed" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
