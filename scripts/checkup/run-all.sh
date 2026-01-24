#!/bin/bash
# run-all.sh - Main runner for FreeSWITCH-ARM Production Readiness Checkup
# Part of FreeSWITCH-ARM Production Readiness Checkup

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# Version
readonly VERSION="1.0.0"

# =============================================================================
# Configuration
# =============================================================================

BACKEND_URL="${BACKEND_URL:-}"
SKIP_BUILD="${SKIP_BUILD:-false}"
CATEGORIES=("docker" "integration" "telephony" "performance" "security")
SELECTED_CATEGORIES=()

# Results storage
declare -A CATEGORY_RESULTS
declare -A CATEGORY_PASSED
declare -A CATEGORY_TOTAL
OVERALL_PASSED=0
OVERALL_TOTAL=0
START_TIME=$(date +%s)

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
FreeSWITCH-ARM Production Readiness Checkup v${VERSION}

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --backend-url URL    URL of the pbx-backend-core API (required for integration tests)
    --container NAME     Name of the FreeSWITCH container (default: freeswitch)
    --image NAME         Name of the FreeSWITCH image (default: freeswitch-arm:latest)
    --skip-build         Skip Docker build validation
    --category CAT       Run only specific category (docker|integration|telephony|performance|security)
                         Can be specified multiple times
    --json, -j           Output results as JSON
    --verbose, -v        Enable verbose output
    --help, -h           Show this help message

CATEGORIES:
    docker       Validate Docker image and container (P1)
    integration  Validate xml_curl backend integration (P1)
    telephony    Validate SIP functionality (P2)
    performance  Validate performance configuration (P2)
    security     Validate security configuration (P3)

EXAMPLES:
    # Run all checks
    $(basename "$0") --backend-url http://localhost:3000

    # Run only P1 (critical) checks
    $(basename "$0") --backend-url http://localhost:3000 --category docker --category integration

    # Run with JSON output
    $(basename "$0") --backend-url http://localhost:3000 --json

    # Skip build validation (image already exists)
    $(basename "$0") --backend-url http://localhost:3000 --skip-build

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend-url)
                BACKEND_URL="$2"
                shift 2
                ;;
            --container)
                FREESWITCH_CONTAINER="$2"
                shift 2
                ;;
            --image)
                FREESWITCH_IMAGE="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --category)
                SELECTED_CATEGORIES+=("$2")
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

    # If no categories selected, run all
    if [[ ${#SELECTED_CATEGORIES[@]} -eq 0 ]]; then
        SELECTED_CATEGORIES=("${CATEGORIES[@]}")
    fi

    # Validate categories
    for cat in "${SELECTED_CATEGORIES[@]}"; do
        local valid=false
        for valid_cat in "${CATEGORIES[@]}"; do
            if [[ "$cat" == "$valid_cat" ]]; then
                valid=true
                break
            fi
        done
        if [[ "$valid" != "true" ]]; then
            log_error "Invalid category: $cat"
            log_error "Valid categories: ${CATEGORIES[*]}"
            exit 1
        fi
    done

    # Check backend URL requirement
    for cat in "${SELECTED_CATEGORIES[@]}"; do
        if [[ "$cat" == "integration" && -z "$BACKEND_URL" ]]; then
            log_error "--backend-url is required for integration tests"
            exit 1
        fi
    done
}

# =============================================================================
# Category Runners
# =============================================================================

run_category() {
    local category="$1"
    local script="${SCRIPT_DIR}/${category}.sh"
    local script_numbered=""
    
    # Find the script with number prefix
    case "$category" in
        docker)      script_numbered="${SCRIPT_DIR}/01-docker-validation.sh" ;;
        integration) script_numbered="${SCRIPT_DIR}/02-integration.sh" ;;
        telephony)   script_numbered="${SCRIPT_DIR}/03-telephony.sh" ;;
        performance) script_numbered="${SCRIPT_DIR}/04-performance.sh" ;;
        security)    script_numbered="${SCRIPT_DIR}/05-security.sh" ;;
    esac

    if [[ ! -f "$script_numbered" ]]; then
        log_warn "Script not found: $script_numbered (skipping $category)"
        CATEGORY_RESULTS[$category]="skipped"
        return 0
    fi

    # Build arguments
    local args=()
    [[ "$VERBOSE" == "true" ]] && args+=("--verbose")
    [[ "$JSON_OUTPUT" == "true" ]] && args+=("--json")
    [[ -n "$FREESWITCH_CONTAINER" ]] && args+=("--container" "$FREESWITCH_CONTAINER")
    [[ -n "$FREESWITCH_IMAGE" ]] && args+=("--image" "$FREESWITCH_IMAGE")
    
    case "$category" in
        docker)
            [[ "$SKIP_BUILD" == "true" ]] && args+=("--skip-build")
            ;;
        integration)
            args+=("--backend-url" "$BACKEND_URL")
            ;;
    esac

    # Execute script
    local output
    local exit_code=0
    
    if output=$("$script_numbered" "${args[@]}" 2>&1); then
        CATEGORY_RESULTS[$category]="passed"
    else
        exit_code=$?
        CATEGORY_RESULTS[$category]="failed"
    fi

    # Parse results from output if JSON
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "$output"
    else
        echo "$output"
    fi

    return $exit_code
}

# =============================================================================
# Console Output
# =============================================================================

print_header() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return
    fi
    
    local width=64
    local title="FreeSWITCH-ARM Production Readiness Checkup"
    
    echo ""
    echo -e "${BOX_TL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_TR}"
    printf "${BOX_V}%*s${BOX_V}\n" $(((width+${#title})/2)) "$title"
    echo -e "${BOX_ML}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_MR}"
    
    # Environment info
    printf "${BOX_V} %-30s %-31s ${BOX_V}\n" "Host: $(hostname)" "Arch: $(uname -m)"
    printf "${BOX_V} %-30s %-31s ${BOX_V}\n" "Docker: $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')" "Date: $(date '+%Y-%m-%d %H:%M')"
    
    echo -e "${BOX_ML}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_MR}"
}

print_category_result() {
    local category="$1"
    local result="${CATEGORY_RESULTS[$category]:-unknown}"
    local priority=""
    local passed="${2:-0}"
    local total="${3:-0}"
    
    case "$category" in
        docker|integration) priority="P1" ;;
        telephony|performance) priority="P2" ;;
        security) priority="P3" ;;
    esac
    
    local status_icon
    case "$result" in
        passed)  status_icon="${GREEN}${CHECKMARK} PASSED${NC}" ;;
        failed)  status_icon="${RED}${CROSSMARK} FAILED${NC}" ;;
        skipped) status_icon="${DIM}⊘ SKIPPED${NC}" ;;
        *)       status_icon="${YELLOW}? UNKNOWN${NC}" ;;
    esac
    
    local category_name
    case "$category" in
        docker)      category_name="Docker Validation" ;;
        integration) category_name="Integration" ;;
        telephony)   category_name="Telephony" ;;
        performance) category_name="Performance" ;;
        security)    category_name="Security" ;;
    esac
    
    printf "${BOX_V} [%s] %-25s %s (%d/%d) ${BOX_V}\n" "$priority" "$category_name" "$status_icon" "$passed" "$total"
}

print_summary() {
    local duration=$(($(date +%s) - START_TIME))
    local mins=$((duration / 60))
    local secs=$((duration % 60))
    local duration_str="${mins}m ${secs}s"
    
    local p1_failed=false
    for cat in docker integration; do
        if [[ "${CATEGORY_RESULTS[$cat]:-}" == "failed" ]]; then
            p1_failed=true
            break
        fi
    done
    
    local production_ready=true
    for cat in "${SELECTED_CATEGORIES[@]}"; do
        if [[ "${CATEGORY_RESULTS[$cat]:-}" == "failed" ]]; then
            production_ready=false
            break
        fi
    done

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BOX_ML}$(printf '%*s' 64 '' | tr ' ' "$BOX_H")${BOX_MR}"
        printf "${BOX_V} %-30s %-31s ${BOX_V}\n" "Total: ${OVERALL_PASSED}/${OVERALL_TOTAL}" "Duration: ${duration_str}"
        
        if [[ "$production_ready" == "true" ]]; then
            printf "${BOX_V} %-62s ${BOX_V}\n" "Status: ${GREEN}${CHECKMARK} PRODUCTION READY${NC}"
        elif [[ "$p1_failed" == "true" ]]; then
            printf "${BOX_V} %-62s ${BOX_V}\n" "Status: ${RED}${CROSSMARK} NOT PRODUCTION READY (P1 FAILED)${NC}"
        else
            printf "${BOX_V} %-62s ${BOX_V}\n" "Status: ${YELLOW}${WARNING} WARNINGS - Review failed checks${NC}"
        fi
        
        echo -e "${BOX_BL}$(printf '%*s' 64 '' | tr ' ' "$BOX_H")${BOX_BR}"
    fi
}

# =============================================================================
# JSON Output
# =============================================================================

generate_full_json() {
    local duration=$(($(date +%s) - START_TIME))
    local production_ready=true
    
    for cat in "${SELECTED_CATEGORIES[@]}"; do
        if [[ "${CATEGORY_RESULTS[$cat]:-}" == "failed" ]]; then
            production_ready=false
            break
        fi
    done
    
    cat <<EOF
{
    "id": "$(generate_uuid)",
    "timestamp": "$(get_timestamp)",
    "version": "$VERSION",
    "environment": {
        "hostname": "$(hostname)",
        "architecture": "$(uname -m)",
        "docker_version": "$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')",
        "backend_url": "$BACKEND_URL"
    },
    "summary": {
        "total_checks": $OVERALL_TOTAL,
        "passed": $OVERALL_PASSED,
        "failed": $((OVERALL_TOTAL - OVERALL_PASSED)),
        "pass_rate": $(if [[ $OVERALL_TOTAL -gt 0 ]]; then echo "scale=0; $OVERALL_PASSED * 100 / $OVERALL_TOTAL" | bc; else echo 0; fi),
        "production_ready": $production_ready
    },
    "duration_seconds": $duration
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    print_header
    
    local all_passed=true
    
    for category in "${SELECTED_CATEGORIES[@]}"; do
        if ! run_category "$category"; then
            all_passed=false
        fi
    done
    
    print_summary
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_full_json
    fi
    
    if [[ "$all_passed" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
