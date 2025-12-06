#!/bin/bash
# Spec compliance test runner for try
# Usage: ./runner.sh /path/to/try
#        ./runner.sh "valgrind -q --leak-check=full --error-exitcode=1 ./dist/try"

# Don't exit on command errors - we handle failures via pass/fail
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="$(dirname "$SCRIPT_DIR")"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/try"
    echo "       $0 \"valgrind -q --leak-check=full --error-exitcode=1 /path/to/try\""
    echo ""
    echo "Run spec compliance tests against a try implementation."
    echo "Supports command wrappers like valgrind for memory checking."
    exit 1
fi

TRY_CMD="$1"

# Extract the actual binary path (last space-separated token that looks like a path)
TRY_BIN_PATH=$(echo "$TRY_CMD" | awk '{print $NF}')

# Convert binary path to absolute if it's relative (needed for tests that cd)
if [[ "$TRY_BIN_PATH" != /* ]]; then
    ABS_BIN_PATH="$(cd "$(dirname "$TRY_BIN_PATH")" && pwd)/$(basename "$TRY_BIN_PATH")"
    TRY_CMD="${TRY_CMD/$TRY_BIN_PATH/$ABS_BIN_PATH}"
    TRY_BIN_PATH="$ABS_BIN_PATH"
fi

# Verify binary exists and is executable
if [ ! -x "$TRY_BIN_PATH" ]; then
    echo -e "${RED}Error: '$TRY_BIN_PATH' is not executable or does not exist${NC}"
    exit 1
fi

# Export for test scripts
export TRY_CMD
export TRY_BIN_PATH
export SPEC_DIR

# Set invariant terminal size for tests (can be overridden by specific tests)
export TRY_WIDTH=80
export TRY_HEIGHT=24

# Helper function to run try with proper command expansion
# Usage: try_run [args...]
# This allows TRY_CMD to be "valgrind ./dist/try" and still work
# Captures both stdout and stderr, returns exit code
# Captures memory error output to ERROR_FILE for reporting
try_run() {
    local output exit_code
    output=$(eval $TRY_CMD '"$@"' 2>&1)
    exit_code=$?
    echo "$output"
    # Capture any memory error output (works with valgrind, sanitizers, etc.)
    if echo "$output" | grep -qE "(definitely lost|indirectly lost|Invalid read|Invalid write|uninitialised|AddressSanitizer|LeakSanitizer)"; then
        echo "$output" >> "$ERROR_FILE"
    fi
    return $exit_code
}

# Create test environment
export TEST_ROOT=$(mktemp -d)
export TEST_TRIES="$TEST_ROOT/tries"
mkdir -p "$TEST_TRIES"

# Create test directories with different mtimes
mkdir -p "$TEST_TRIES/2025-11-01-alpha"
mkdir -p "$TEST_TRIES/2025-11-15-beta"
mkdir -p "$TEST_TRIES/2025-11-20-gamma"
mkdir -p "$TEST_TRIES/2025-11-25-project-with-long-name"
mkdir -p "$TEST_TRIES/no-date-prefix"

# Set mtimes (oldest first)
# Use -t format (YYYYMMDDhhmm) which works on both macOS and Linux
touch -t 202511010000 "$TEST_TRIES/2025-11-01-alpha"
touch -t 202511150000 "$TEST_TRIES/2025-11-15-beta"
touch -t 202511200000 "$TEST_TRIES/2025-11-20-gamma"
touch -t 202511250000 "$TEST_TRIES/2025-11-25-project-with-long-name"
touch "$TEST_TRIES/no-date-prefix"  # Most recent

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Track error output (memory leaks, invalid accesses, etc.) via temp file
# (needed because try_run is called in subshells via command substitution)
export ERROR_FILE=$(mktemp)

# Test utilities - exported for test scripts
pass() {
    echo -en "${GREEN}.${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
    echo -e "\n${RED}FAIL${NC}: $1"
    local msg="FAIL: $1"
    if [ -n "$2" ]; then
        echo "  Expected: $2"
        msg="$msg\n  Expected: $2"
    fi
    if [ -n "$3" ]; then
        echo -e "\n  Command output:\n\n$3\n"
        msg="$msg\n  Command output:\n$3"
    fi
    if [ -n "$4" ]; then
        echo -e "  ${YELLOW}Spec: $SPEC_DIR/$4${NC}"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

section() {
    echo -en "\n${YELLOW}$1${NC} "
}

export -f pass fail section try_run

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_ROOT"
    rm -f "$ERROR_FILE"
}
trap cleanup EXIT

# Header
echo "Testing: $TRY_CMD"
echo "Spec dir: $SPEC_DIR"
echo "Test env: $TEST_TRIES"
echo

# Run all test_*.sh files in order
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    if [ -f "$test_file" ]; then
        # Reset error handling before each test file (some tests use set -e internally)
        set +e
        # Source the test file to run in same environment
        source "$test_file"
    fi
done

# Summary
echo
echo
echo "═══════════════════════════════════"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"

EXIT_CODE=0

# Check for memory errors first (valgrind, sanitizers)
if [ -s "$ERROR_FILE" ]; then
    echo -e "${RED}Memory errors detected${NC}"
    echo -e "${YELLOW}Error output:${NC}"
    grep -E "(definitely lost|indirectly lost|Invalid|uninitialised|Sanitizer|at 0x|by 0x)" "$ERROR_FILE" | head -30
    EXIT_CODE=1
fi

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}$TESTS_FAILED tests failed${NC}"
    EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All tests passed${NC}"
fi

exit $EXIT_CODE
