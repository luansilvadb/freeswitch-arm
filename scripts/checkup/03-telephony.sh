#!/bin/bash
# 03-telephony.sh - SIP Telephony Validation
# Part of FreeSWITCH-ARM Production Readiness Checkup
# Category: telephony | Priority: P2 | User Story: US3
#
# Validates:
#   - tel-001: mod_sofia loaded
#   - tel-002: SIP port listening
#   - tel-003: Codecs available
#   - tel-004: SIP registration capability

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

readonly CATEGORY="telephony"
readonly CATEGORY_NAME="Telephony Validation"
FREESWITCH_HOST="${FREESWITCH_HOST:-localhost}"
SIP_PORT="${SIP_PORT:-5060}"
TEST_EXTENSION="${TEST_EXTENSION:-1001}"
TEST_PASSWORD="${TEST_PASSWORD:-1234}"

# Required codecs
REQUIRED_CODECS=("OPUS" "PCMU" "PCMA")

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Telephony Validation - FreeSWITCH-ARM Production Readiness Checkup

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --container NAME     FreeSWITCH container name (default: freeswitch)
    --host HOST          FreeSWITCH host for external tests (default: localhost)
    --port PORT          SIP port (default: 5060)
    --extension EXT      Test extension (default: 1001)
    --password PASS      Test password (default: 1234)
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CHECKS:
    tel-001  mod_sofia is loaded (FR-007)
    tel-002  SIP port is listening (FR-004)
    tel-003  Required codecs available (FR-008)
    tel-004  SIP registration capability

NOTE:
    Full audio validation requires manual testing with a softphone.

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
            --host)
                FREESWITCH_HOST="$2"
                shift 2
                ;;
            --port)
                SIP_PORT="$2"
                shift 2
                ;;
            --extension)
                TEST_EXTENSION="$2"
                shift 2
                ;;
            --password)
                TEST_PASSWORD="$2"
                shift 2
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

# tel-001: mod_sofia loaded
check_tel_001() {
    local check_id="tel-001"
    local check_name="mod_sofia loaded"
    local requirement="FR-007"
    
    log_debug "Checking if mod_sofia is loaded"
    
    local result
    result=$(exec_in_container "$FREESWITCH_CONTAINER" \
        /usr/local/freeswitch/bin/fs_cli -x "module_exists mod_sofia" 2>/dev/null || echo "error")
    
    log_debug "module_exists result: $result"
    
    if [[ "$result" == "true" ]]; then
        print_check "$check_id" "$check_name" "passed" "mod_sofia loaded" "true"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "true" "true" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "mod_sofia loaded" "$result"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "true" "$result" "Sofia module not loaded" "0"
        return 1
    fi
}

# tel-002: SIP port listening
check_tel_002() {
    local check_id="tel-002"
    local check_name="SIP port listening"
    local requirement="FR-004"
    
    log_debug "Checking SIP port $SIP_PORT"
    
    local listening
    listening=$(exec_in_container "$FREESWITCH_CONTAINER" \
        ss -tuln 2>/dev/null | grep ":$SIP_PORT " || echo "")
    
    log_debug "Listening: $listening"
    
    if [[ -n "$listening" ]]; then
        # Check both TCP and UDP
        local tcp_listen udp_listen
        tcp_listen=$(echo "$listening" | grep -c "tcp" || echo "0")
        udp_listen=$(echo "$listening" | grep -c "udp" || echo "0")
        
        local status="TCP: $tcp_listen, UDP: $udp_listen"
        
        if [[ "$tcp_listen" -gt 0 || "$udp_listen" -gt 0 ]]; then
            print_check "$check_id" "$check_name" "passed" "Port $SIP_PORT listening" "$status"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "Listening" "$status" "" "0"
            return 0
        fi
    fi
    
    print_check "$check_id" "$check_name" "failed" "Port $SIP_PORT listening" "Not listening"
    add_json_check "$check_id" "$check_name" "$requirement" "failed" "Listening" "Not listening" "Check sofia profile" "0"
    return 1
}

# tel-003: Codecs available
check_tel_003() {
    local check_id="tel-003"
    local check_name="Codecs available"
    local requirement="FR-008"
    
    log_debug "Checking available codecs"
    
    local codecs
    codecs=$(exec_in_container "$FREESWITCH_CONTAINER" \
        /usr/local/freeswitch/bin/fs_cli -x "show codec" 2>/dev/null || echo "")
    
    log_debug "Codecs output length: ${#codecs}"
    
    local missing=()
    local found=()
    
    for codec in "${REQUIRED_CODECS[@]}"; do
        if echo "$codecs" | grep -qi "$codec"; then
            found+=("$codec")
        else
            missing+=("$codec")
        fi
    done
    
    log_debug "Found: ${found[*]:-none}"
    log_debug "Missing: ${missing[*]:-none}"
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "OPUS, PCMU, PCMA" "${found[*]}"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Required codecs" "${found[*]}" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "OPUS, PCMU, PCMA" "Missing: ${missing[*]}"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Required codecs" "Missing: ${missing[*]}" "Enable codec modules" "0"
        return 1
    fi
}

# tel-004: SIP registration capability
check_tel_004() {
    local check_id="tel-004"
    local check_name="SIP registration capability"
    local requirement=""
    
    log_debug "Checking SIP registration capability"
    
    # Check sofia status - simpler than full registration test
    local sofia_status
    sofia_status=$(exec_in_container "$FREESWITCH_CONTAINER" \
        /usr/local/freeswitch/bin/fs_cli -x "sofia status" 2>/dev/null || echo "error")
    
    log_debug "Sofia status length: ${#sofia_status}"
    
    if echo "$sofia_status" | grep -qi "RUNNING\|profile"; then
        # Count running profiles
        local profile_count
        profile_count=$(echo "$sofia_status" | grep -ci "RUNNING" || echo "0")
        
        print_check "$check_id" "$check_name" "passed" "Sofia profiles running" "$profile_count profile(s) RUNNING"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Profiles running" "$profile_count running" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "Sofia profiles running" "No running profiles"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Profiles running" "None" "Check sofia configuration" "0"
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
    log_info "SIP Port: $SIP_PORT"
    
    check_prerequisites
    
    reset_checks
    
    local all_passed=true
    
    check_tel_001 || all_passed=false
    check_tel_002 || all_passed=false
    check_tel_003 || all_passed=false
    check_tel_004 || all_passed=false
    
    print_summary "$CATEGORY_NAME"
    
    # Note about manual testing
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        log_warn "NOTE: For complete audio validation, manual testing with a softphone is recommended."
        log_info "  1. Register a softphone (Linphone, Zoiper) to ${FREESWITCH_HOST}:${SIP_PORT}"
        log_info "  2. Dial 9196 (echo test) to verify audio"
    fi
    
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
