#!/bin/bash
# 02-integration.sh - Backend Integration Validation (xml_curl)
# Part of FreeSWITCH-ARM Production Readiness Checkup
# Category: integration | Priority: P1 | User Story: US2
#
# Validates:
#   - int-001: mod_xml_curl module loaded
#   - int-002: XML_CURL_URL configured
#   - int-003: Configuration request works
#   - int-004: Directory request works
#   - int-005: Dialplan request works

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

readonly CATEGORY="integration"
readonly CATEGORY_NAME="Integration Validation"
BACKEND_URL="${BACKEND_URL:-}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Integration Validation - FreeSWITCH-ARM Production Readiness Checkup

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --backend-url URL    Backend API URL (REQUIRED)
    --container NAME     FreeSWITCH container name (default: freeswitch)
    --timeout SECS       HTTP timeout in seconds (default: 10)
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CHECKS:
    int-001  mod_xml_curl module is loaded (FR-002)
    int-002  XML_CURL_URL is configured (FR-003)
    int-003  Configuration request works (FR-010)
    int-004  Directory request works (FR-010)
    int-005  Dialplan request works (FR-010)

EXAMPLE:
    $(basename "$0") --backend-url http://backend:3000

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend-url|-b)
                BACKEND_URL="$2"
                shift 2
                ;;
            --container|-c)
                FREESWITCH_CONTAINER="$2"
                shift 2
                ;;
            --timeout|-t)
                HTTP_TIMEOUT="$2"
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
    
    # Validate required arguments
    if [[ -z "$BACKEND_URL" ]]; then
        log_error "--backend-url is required"
        show_help
        exit 2
    fi
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    # Check container is running
    if ! container_running "$FREESWITCH_CONTAINER"; then
        log_error "Container '$FREESWITCH_CONTAINER' is not running"
        log_error "Start the container first: docker start $FREESWITCH_CONTAINER"
        exit 3
    fi
    
    # Check backend connectivity
    log_debug "Checking backend connectivity: $BACKEND_URL"
    
    local health_url="${BACKEND_URL}/health"
    local alt_url="${BACKEND_URL}/"
    
    if curl -sf --max-time "$HTTP_TIMEOUT" "$health_url" >/dev/null 2>&1 || \
       curl -sf --max-time "$HTTP_TIMEOUT" "$alt_url" >/dev/null 2>&1; then
        log_debug "Backend is accessible"
    else
        log_warn "Backend may not be accessible at $BACKEND_URL"
        log_warn "Some checks may fail if backend is not running"
    fi
}

# =============================================================================
# Checks
# =============================================================================

# int-001: mod_xml_curl module loaded
check_int_001() {
    local check_id="int-001"
    local check_name="mod_xml_curl module loaded"
    local requirement="FR-002"
    
    log_debug "Checking if mod_xml_curl is loaded"
    
    local result
    result=$(exec_in_container "$FREESWITCH_CONTAINER" \
        /usr/local/freeswitch/bin/fs_cli -x "module_exists mod_xml_curl" 2>/dev/null || echo "error")
    
    log_debug "module_exists result: $result"
    
    if [[ "$result" == "true" ]]; then
        print_check "$check_id" "$check_name" "passed" "mod_xml_curl loaded" "true"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "true" "true" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "mod_xml_curl loaded" "$result" "Module not loaded or fs_cli failed"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "true" "$result" "Load mod_xml_curl in modules.conf.xml" "0"
        return 1
    fi
}

# int-002: XML_CURL_URL configured
check_int_002() {
    local check_id="int-002"
    local check_name="XML_CURL_URL configured"
    local requirement="FR-003"
    
    log_debug "Checking xml_curl configuration"
    
    local config_file="/usr/local/freeswitch/conf/autoload_configs/xml_curl.conf.xml"
    local config
    config=$(exec_in_container "$FREESWITCH_CONTAINER" cat "$config_file" 2>/dev/null || echo "")
    
    if [[ -z "$config" ]]; then
        print_check "$check_id" "$check_name" "failed" "gateway-url configured" "Config file not found"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Config exists" "File not found" "$config_file missing" "0"
        return 1
    fi
    
    # Extract gateway-url
    local gateway_url
    gateway_url=$(echo "$config" | grep -oP 'gateway-url[^"]*value="\K[^"]+' || echo "")
    
    log_debug "Gateway URL: $gateway_url"
    
    if [[ -n "$gateway_url" ]]; then
        print_check "$check_id" "$check_name" "passed" "gateway-url configured" "$gateway_url"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "URL present" "$gateway_url" "" "0"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "gateway-url configured" "Not found in config"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "URL present" "Not configured" "Set XML_CURL_URL environment variable" "0"
        return 1
    fi
}

# int-003: Configuration request works
check_int_003() {
    local check_id="int-003"
    local check_name="Configuration request works"
    local requirement="FR-010"
    
    local endpoint="${BACKEND_URL}/freeswitch/xml"
    
    log_debug "Testing configuration request to: $endpoint"
    
    local response
    local http_code
    
    # Make configuration request
    response=$(curl -s --max-time "$HTTP_TIMEOUT" \
        -X POST "$endpoint" \
        -d "section=configuration" \
        -d "tag_name=configuration" \
        -d "key_name=name" \
        -d "key_value=sofia.conf" \
        -w "\n%{http_code}" 2>/dev/null || echo -e "\n000")
    
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Code: $http_code"
    log_debug "Response body length: ${#body}"
    
    if [[ "$http_code" == "200" ]]; then
        # Check if response is valid XML
        if echo "$body" | grep -q "<?xml\|<document\|<section"; then
            print_check "$check_id" "$check_name" "passed" "HTTP 200 with valid XML" "Status: $http_code, XML received"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "200 OK" "$http_code" "" "0"
            return 0
        else
            print_check "$check_id" "$check_name" "failed" "Valid XML response" "Status: $http_code, but response is not XML"
            add_json_check "$check_id" "$check_name" "$requirement" "failed" "XML response" "Not XML" "Response is not valid XML" "0"
            return 1
        fi
    else
        print_check "$check_id" "$check_name" "failed" "HTTP 200" "HTTP $http_code" "Backend returned error"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "200 OK" "$http_code" "Check backend logs" "0"
        return 1
    fi
}

# int-004: Directory request works
check_int_004() {
    local check_id="int-004"
    local check_name="Directory request works"
    local requirement="FR-010"
    
    local endpoint="${BACKEND_URL}/freeswitch/xml"
    
    log_debug "Testing directory request to: $endpoint"
    
    local response
    local http_code
    
    response=$(curl -s --max-time "$HTTP_TIMEOUT" \
        -X POST "$endpoint" \
        -d "section=directory" \
        -d "tag_name=domain" \
        -d "key_name=name" \
        -d "key_value=default" \
        -d "user=1001" \
        -d "domain=default" \
        -w "\n%{http_code}" 2>/dev/null || echo -e "\n000")
    
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Code: $http_code"
    
    if [[ "$http_code" == "200" ]]; then
        if echo "$body" | grep -qi "directory\|document\|<?xml"; then
            print_check "$check_id" "$check_name" "passed" "Directory XML response" "Status: $http_code"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "200 OK" "$http_code" "" "0"
            return 0
        else
            print_check "$check_id" "$check_name" "passed" "HTTP 200 response" "Status: $http_code (empty/not found is OK)"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "200 OK" "$http_code" "Empty response acceptable" "0"
            return 0
        fi
    else
        print_check "$check_id" "$check_name" "failed" "HTTP 200" "HTTP $http_code"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "200 OK" "$http_code" "Directory lookup failed" "0"
        return 1
    fi
}

# int-005: Dialplan request works
check_int_005() {
    local check_id="int-005"
    local check_name="Dialplan request works"
    local requirement="FR-010"
    
    local endpoint="${BACKEND_URL}/freeswitch/xml"
    
    log_debug "Testing dialplan request to: $endpoint"
    
    local response
    local http_code
    
    response=$(curl -s --max-time "$HTTP_TIMEOUT" \
        -X POST "$endpoint" \
        -d "section=dialplan" \
        -d "tag_name=context" \
        -d "key_name=name" \
        -d "key_value=default" \
        -d "Caller-Context=default" \
        -w "\n%{http_code}" 2>/dev/null || echo -e "\n000")
    
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Code: $http_code"
    
    if [[ "$http_code" == "200" ]]; then
        if echo "$body" | grep -qi "dialplan\|document\|<?xml\|context"; then
            print_check "$check_id" "$check_name" "passed" "Dialplan XML response" "Status: $http_code"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "200 OK" "$http_code" "" "0"
            return 0
        else
            print_check "$check_id" "$check_name" "passed" "HTTP 200 response" "Status: $http_code"
            add_json_check "$check_id" "$check_name" "$requirement" "passed" "200 OK" "$http_code" "" "0"
            return 0
        fi
    else
        print_check "$check_id" "$check_name" "failed" "HTTP 200" "HTTP $http_code"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "200 OK" "$http_code" "Dialplan lookup failed" "0"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    log_header "$CATEGORY_NAME"
    log_info "Backend URL: $BACKEND_URL"
    log_info "Container: $FREESWITCH_CONTAINER"
    
    check_prerequisites
    
    reset_checks
    
    local all_passed=true
    
    check_int_001 || all_passed=false
    check_int_002 || all_passed=false
    check_int_003 || all_passed=false
    check_int_004 || all_passed=false
    check_int_005 || all_passed=false
    
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
