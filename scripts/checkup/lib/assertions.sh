#!/bin/bash
# assertions.sh - Assertion functions for checkup validation
# Part of FreeSWITCH-ARM Production Readiness Checkup

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# JSON results array (populated during checks)
declare -a JSON_CHECKS=()

# Assert that two values are equal
# Usage: assert_equals "check_id" "check_name" "requirement" "expected" "actual"
assert_equals() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local expected="$4"
    local actual="$5"
    local start_time
    start_time=$(date +%s%3N)
    
    if [[ "$expected" == "$actual" ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "passed" "$expected" "$actual"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "$expected" "$actual" "" "$duration"
        return 0
    else
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" "$expected" "$actual" "Values do not match"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "$expected" "$actual" "Values do not match" "$duration"
        return 1
    fi
}

# Assert that actual contains expected substring
# Usage: assert_contains "check_id" "check_name" "requirement" "expected_substr" "actual"
assert_contains() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local expected="$4"
    local actual="$5"
    local start_time
    start_time=$(date +%s%3N)
    
    if [[ "$actual" == *"$expected"* ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "passed" "Contains: $expected" "$actual"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Contains: $expected" "$actual" "" "$duration"
        return 0
    else
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" "Contains: $expected" "$actual" "Substring not found"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Contains: $expected" "$actual" "Substring not found" "$duration"
        return 1
    fi
}

# Assert that actual does NOT contain substring
# Usage: assert_not_contains "check_id" "check_name" "requirement" "unexpected_substr" "actual"
assert_not_contains() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local unexpected="$4"
    local actual="$5"
    local start_time
    start_time=$(date +%s%3N)
    
    if [[ "$actual" != *"$unexpected"* ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "passed" "Does not contain: $unexpected" "(clean)"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "Does not contain: $unexpected" "(clean)" "" "$duration"
        return 0
    else
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" "Does not contain: $unexpected" "Found: $unexpected"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "Does not contain: $unexpected" "Found: $unexpected" "Unexpected content found" "$duration"
        return 1
    fi
}

# Assert that a command succeeds (exit code 0)
# Usage: assert_command_succeeds "check_id" "check_name" "requirement" "description" command args...
assert_command_succeeds() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local description="$4"
    shift 4
    local start_time
    start_time=$(date +%s%3N)
    
    local output
    local exit_code
    
    output=$("$@" 2>&1)
    exit_code=$?
    
    local duration=$(($(date +%s%3N) - start_time))
    
    if [[ $exit_code -eq 0 ]]; then
        print_check "$check_id" "$check_name" "passed" "$description" "Command succeeded"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "$description" "Command succeeded (exit 0)" "" "$duration"
        return 0
    else
        print_check "$check_id" "$check_name" "failed" "$description" "Exit code: $exit_code" "$output"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "$description" "Exit code: $exit_code" "$output" "$duration"
        return 1
    fi
}

# Assert that a numeric value is greater than or equal to threshold
# Usage: assert_gte "check_id" "check_name" "requirement" threshold actual
assert_gte() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local threshold="$4"
    local actual="$5"
    local start_time
    start_time=$(date +%s%3N)
    
    # Extract numeric value if needed
    local numeric_actual
    numeric_actual=$(echo "$actual" | grep -oE '[0-9]+' | head -1)
    
    if [[ -z "$numeric_actual" ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" ">= $threshold" "$actual" "Could not extract numeric value"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" ">= $threshold" "$actual" "Could not extract numeric value" "$duration"
        return 1
    fi
    
    if [[ "$numeric_actual" -ge "$threshold" ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "passed" ">= $threshold" "$numeric_actual"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" ">= $threshold" "$numeric_actual" "" "$duration"
        return 0
    else
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" ">= $threshold" "$numeric_actual" "Value below threshold"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" ">= $threshold" "$numeric_actual" "Value below threshold" "$duration"
        return 1
    fi
}

# Assert that a value is true/truthy
# Usage: assert_true "check_id" "check_name" "requirement" "description" value
assert_true() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local description="$4"
    local value="$5"
    local start_time
    start_time=$(date +%s%3N)
    
    if [[ "$value" == "true" || "$value" == "1" || "$value" == "yes" ]]; then
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "passed" "$description: true" "$value"
        add_json_check "$check_id" "$check_name" "$requirement" "passed" "true" "$value" "" "$duration"
        return 0
    else
        local duration=$(($(date +%s%3N) - start_time))
        print_check "$check_id" "$check_name" "failed" "$description: true" "$value"
        add_json_check "$check_id" "$check_name" "$requirement" "failed" "true" "$value" "Expected truthy value" "$duration"
        return 1
    fi
}

# Skip a check with reason
# Usage: skip_check "check_id" "check_name" "requirement" "reason"
skip_check() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local reason="$4"
    
    print_check "$check_id" "$check_name" "skipped" "N/A" "N/A" "$reason"
    add_json_check "$check_id" "$check_name" "$requirement" "skipped" "N/A" "N/A" "$reason" "0"
}

# Add check result to JSON array
add_json_check() {
    local check_id="$1"
    local check_name="$2"
    local requirement="$3"
    local status="$4"
    local expected="$5"
    local actual="$6"
    local message="$7"
    local duration_ms="$8"
    
    # Escape JSON strings
    check_name="${check_name//\"/\\\"}"
    expected="${expected//\"/\\\"}"
    actual="${actual//\"/\\\"}"
    message="${message//\"/\\\"}"
    
    local json_check
    json_check=$(cat <<EOF
{
    "id": "$check_id",
    "name": "$check_name",
    "requirement": "$requirement",
    "status": "$status",
    "expected": "$expected",
    "actual": "$actual",
    "message": "$message",
    "duration_ms": $duration_ms
}
EOF
)
    JSON_CHECKS+=("$json_check")
}

# Generate JSON output for category
generate_category_json() {
    local category="$1"
    local status
    
    if [[ "$CHECKS_FAILED" -eq 0 ]]; then
        status="passed"
    else
        status="failed"
    fi
    
    local checks_json
    checks_json=$(IFS=,; echo "${JSON_CHECKS[*]}")
    
    cat <<EOF
{
    "category": "$category",
    "status": "$status",
    "checks": [$checks_json],
    "summary": {
        "total": $CHECKS_TOTAL,
        "passed": $CHECKS_PASSED,
        "failed": $CHECKS_FAILED,
        "skipped": $CHECKS_SKIPPED
    }
}
EOF
}

# Reset check counters (for running multiple categories)
reset_checks() {
    CHECKS_PASSED=0
    CHECKS_FAILED=0
    CHECKS_SKIPPED=0
    CHECKS_TOTAL=0
    JSON_CHECKS=()
}
