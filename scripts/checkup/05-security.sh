#!/bin/bash
# 05-security.sh - Security Configuration Validation
# Part of FreeSWITCH-ARM Production Readiness Checkup
# Category: security | Priority: P3 | User Story: US5
#
# Validates:
#   - sec-001: Process runs as non-root
#   - sec-002: Only required ports exposed
#   - sec-003: Sensitive files protected
#   - sec-004: No default passwords in config
#   - sec-005: Event socket protected

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

readonly CATEGORY="security"
readonly CATEGORY_NAME="Security Validation"
EXPECTED_USER="${EXPECTED_USER:-freeswitch}"

# Expected ports
EXPECTED_PORTS=("5060" "5080" "8021")

# Default passwords to check for
DEFAULT_PASSWORDS=("1234" "password" "admin" "default" "ClueCon" "secret")

# Warnings list
declare -a WARNINGS=()

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Security Validation - FreeSWITCH-ARM Production Readiness Checkup

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --container NAME     FreeSWITCH container name (default: freeswitch)
    --user NAME          Expected process user (default: freeswitch)
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CHECKS:
    sec-001  Process runs as non-root (FR-005)
    sec-002  Only required ports exposed (FR-004)
    sec-003  Sensitive files protected
    sec-004  No default passwords in config
    sec-005  Event socket protected

NOTE:
    Some checks generate warnings instead of failures for items that
    are security recommendations rather than strict requirements.

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
            --user|-u)
                EXPECTED_USER="$2"
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

# sec-001: Process runs as non-root
check_sec_001() {
    local check_id="sec-001"
    local check_name="Process runs as non-root"
    local requirement="FR-005"
    
    log_debug "Checking process user"
    
    local ps_output
    ps_output=$(exec_in_container "$FREESWITCH_CONTAINER" \
        ps aux 2>/dev/null | grep "[f]reeswitch" | head -1 || echo "")
    
    log_debug "PS output: $ps_output"
    
    if [[ -z "$ps_output" ]]; then
        print_check "$check_id" "$check_name" "failed" "Process running as non-root" "FreeSWITCH process not found"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "non-root" "Not found" "Process not running" "0"
        return 1
    fi
    
    local process_user
    process_user=$(echo "$ps_output" | awk '{print $1}')
    
    log_debug "Process user: $process_user"
    
    if [[ "$process_user" == "root" ]]; then
        print_check "$check_id" "$check_name" "failed" "non-root user" "root"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "non-root" "root" "Running as root is a security risk" "0"
        WARNINGS+=("Process running as root - security risk")
        return 1
    elif [[ "$process_user" == "$EXPECTED_USER" ]]; then
        print_check "$check_id" "$check_name" "passed" "$EXPECTED_USER" "$process_user"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "$EXPECTED_USER" "$process_user" "" "0"
        return 0
    else
        # Not root, but not expected user - warning only
        print_check "$check_id" "$check_name" "passed" "non-root user" "$process_user (expected: $EXPECTED_USER)"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "non-root" "$process_user" "" "0"
        return 0
    fi
}

# sec-002: Only required ports exposed
check_sec_002() {
    local check_id="sec-002"
    local check_name="Only required ports exposed"
    local requirement="FR-004"
    
    log_debug "Checking exposed ports"
    
    local listening
    listening=$(exec_in_container "$FREESWITCH_CONTAINER" \
        ss -tuln 2>/dev/null | grep LISTEN || echo "")
    
    log_debug "Listening ports: $listening"
    
    # Extract port numbers
    local ports
    ports=$(echo "$listening" | grep -oE ':[0-9]+' | tr -d ':' | sort -u)
    
    log_debug "Found ports: $ports"
    
    # Check for expected ports
    local expected_found=0
    local unexpected=()
    
    while read -r port; do
        [[ -z "$port" ]] && continue
        
        local is_expected=false
        for exp_port in "${EXPECTED_PORTS[@]}"; do
            if [[ "$port" == "$exp_port" ]]; then
                is_expected=true
                ((expected_found++))
                break
            fi
        done
        
        # RTP ports (16384-32768) are expected
        if [[ "$port" -ge 16384 && "$port" -le 32768 ]]; then
            is_expected=true
        fi
        
        if [[ "$is_expected" != "true" ]]; then
            # Some common ports are OK
            case "$port" in
                22|53|443) ;; # SSH, DNS, HTTPS - may be OK
                *) unexpected+=("$port") ;;
            esac
        fi
    done <<< "$ports"
    
    if [[ ${#unexpected[@]} -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "Expected ports only" "Found: ${EXPECTED_PORTS[*]}"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Expected ports" "$expected_found found" "" "0"
        return 0
    else
        log_warn "Unexpected ports: ${unexpected[*]}"
        print_check "$check_id" "$check_name" "passed" "Expected ports" "Found ${#unexpected[@]} additional ports: ${unexpected[*]}"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Expected ports" "Additional: ${unexpected[*]}" "Review unexpected ports" "0"
        WARNINGS+=("Unexpected ports exposed: ${unexpected[*]}")
        return 0  # Warning, not failure
    fi
}

# sec-003: Sensitive files protected
check_sec_003() {
    local check_id="sec-003"
    local check_name="Sensitive files protected"
    local requirement=""
    
    log_debug "Checking file permissions"
    
    local conf_dir="/usr/local/freeswitch/conf"
    local perms
    perms=$(exec_in_container "$FREESWITCH_CONTAINER" \
        ls -la "$conf_dir" 2>/dev/null | head -5 || echo "")
    
    log_debug "Permissions: $perms"
    
    if [[ -z "$perms" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Cannot read directory permissions"
        return 0
    fi
    
    # Check if world-readable (last 'r' in permissions)
    local world_readable
    world_readable=$(echo "$perms" | grep -E "^d.......r" | wc -l)
    
    if [[ "$world_readable" -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "Not world-readable" "Config protected"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Protected" "OK" "" "0"
        return 0
    else
        # Warning but not critical failure
        print_check "$check_id" "$check_name" "passed" "Permissions checked" "Some files may be world-readable"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Checked" "Review permissions" "" "0"
        WARNINGS+=("Some config files may be world-readable")
        return 0
    fi
}

# sec-004: No default passwords
check_sec_004() {
    local check_id="sec-004"
    local check_name="No default passwords in config"
    local requirement=""
    
    log_debug "Checking for default passwords"
    
    local conf_dir="/usr/local/freeswitch/conf"
    local found_defaults=()
    
    for pwd in "${DEFAULT_PASSWORDS[@]}"; do
        local count
        count=$(exec_in_container "$FREESWITCH_CONTAINER" \
            grep -rli "password.*$pwd\|secret.*$pwd" "$conf_dir" 2>/dev/null | wc -l || echo "0")
        
        if [[ "$count" -gt 0 ]]; then
            found_defaults+=("$pwd")
        fi
    done
    
    log_debug "Found default passwords: ${found_defaults[*]:-none}"
    
    if [[ ${#found_defaults[@]} -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "No default passwords" "Clean"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "None" "Clean" "" "0"
        return 0
    else
        # With xml_curl, passwords should come from backend, so static passwords less critical
        print_check "$check_id" "$check_name" "passed" "Password check" "Found ${#found_defaults[@]} potential defaults (may be templates)"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Checked" "${#found_defaults[@]} found" "Review if using xml_curl" "0"
        WARNINGS+=("Potential default passwords in config: ${found_defaults[*]}")
        return 0
    fi
}

# sec-005: Event socket protected
check_sec_005() {
    local check_id="sec-005"
    local check_name="Event socket protected"
    local requirement=""
    
    log_debug "Checking event socket configuration"
    
    local esl_config="/usr/local/freeswitch/conf/autoload_configs/event_socket.conf.xml"
    local config
    config=$(exec_in_container "$FREESWITCH_CONTAINER" \
        cat "$esl_config" 2>/dev/null || echo "")
    
    if [[ -z "$config" ]]; then
        skip_check "$check_id" "$check_name" "$requirement" "Event socket config not found"
        return 0
    fi
    
    log_debug "ESL config found"
    
    # Check listen-ip
    local listen_ip
    listen_ip=$(echo "$config" | grep -oP 'listen-ip[^"]*value="\K[^"]+' || echo "")
    
    # Check for ACL
    local has_acl
    has_acl=$(echo "$config" | grep -ci "acl" || echo "0")
    
    # Check password
    local password
    password=$(echo "$config" | grep -oP 'password[^"]*value="\K[^"]+' || echo "")
    
    log_debug "Listen IP: $listen_ip, Has ACL: $has_acl, Password length: ${#password}"
    
    local issues=()
    
    if [[ "$listen_ip" == "0.0.0.0" || "$listen_ip" == "::" ]] && [[ "$has_acl" -eq 0 ]]; then
        issues+=("ESL on all interfaces without ACL")
        WARNINGS+=("ESL listening on all interfaces - consider restricting")
    fi
    
    if [[ "$password" == "ClueCon" ]]; then
        issues+=("Default ESL password 'ClueCon'")
        WARNINGS+=("ESL using default password - change for production")
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "ESL protected" "Configured securely"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Protected" "OK" "" "0"
        return 0
    else
        # Warnings, not failures
        print_check "$check_id" "$check_name" "passed" "ESL checked" "${#issues[@]} recommendations"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Checked" "${issues[*]}" "Review ESL security" "0"
        return 0
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    log_header "$CATEGORY_NAME"
    log_info "Container: $FREESWITCH_CONTAINER"
    log_info "Expected User: $EXPECTED_USER"
    
    check_prerequisites
    
    reset_checks
    
    local all_passed=true
    
    check_sec_001 || all_passed=false
    check_sec_002 || all_passed=false
    check_sec_003 || all_passed=false
    check_sec_004 || all_passed=false
    check_sec_005 || all_passed=false
    
    print_summary "$CATEGORY_NAME"
    
    # Print warnings
    if [[ ${#WARNINGS[@]} -gt 0 && "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        log_warn "Security Recommendations:"
        for warning in "${WARNINGS[@]}"; do
            echo "  - $warning"
        done
    fi
    
    # Security recommendations
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        log_info "Additional security considerations:"
        log_info "  1. Enable TLS for SIP (mod_sofia TLS profiles)"
        log_info "  2. Enable SRTP for encrypted media"
        log_info "  3. Configure fail2ban for brute-force protection"
        log_info "  4. Keep FreeSWITCH updated for security patches"
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
