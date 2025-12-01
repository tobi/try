#!/bin/bash
# Compare two try implementations by running the same tests against both
# Usage: ./runner_and_compare.sh /path/to/try1 /path/to/try2
#
# Example:
#   ./runner_and_compare.sh ./dist/try ./docs/try.reference.rb

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="$(dirname "$SCRIPT_DIR")"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 /path/to/try1 /path/to/try2"
    echo "Compare two try implementations by running tests against both"
    echo ""
    echo "Example:"
    echo "  $0 ./dist/try ./docs/try.reference.rb"
    exit 1
fi

BIN1="$1"
BIN2="$2"

# Verify binaries exist and are executable
if [ ! -x "$BIN1" ]; then
    echo -e "${RED}Error: '$BIN1' is not executable or does not exist${NC}"
    exit 1
fi
if [ ! -x "$BIN2" ]; then
    echo -e "${RED}Error: '$BIN2' is not executable or does not exist${NC}"
    exit 1
fi

# Create test environment
TEST_ROOT=$(mktemp -d)
TEST_TRIES="$TEST_ROOT/tries"
mkdir -p "$TEST_TRIES"

# Create test directories with different mtimes
mkdir -p "$TEST_TRIES/2025-11-01-alpha"
mkdir -p "$TEST_TRIES/2025-11-15-beta"
mkdir -p "$TEST_TRIES/2025-11-20-gamma"
mkdir -p "$TEST_TRIES/2025-11-25-project-with-long-name"
mkdir -p "$TEST_TRIES/no-date-prefix"

# Set mtimes (oldest first)
touch -d "2025-11-01" "$TEST_TRIES/2025-11-01-alpha"
touch -d "2025-11-15" "$TEST_TRIES/2025-11-15-beta"
touch -d "2025-11-20" "$TEST_TRIES/2025-11-20-gamma"
touch -d "2025-11-25" "$TEST_TRIES/2025-11-25-project-with-long-name"
touch "$TEST_TRIES/no-date-prefix"  # Most recent

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

# Counters
TESTS_SAME=0
TESTS_DIFF=0

# Header
echo "Comparing implementations:"
echo -e "  ${CYAN}A:${NC} $BIN1"
echo -e "  ${CYAN}B:${NC} $BIN2"
echo "Test env: $TEST_TRIES"
echo ""

# Test function: runs a command against both binaries and compares
compare_test() {
    local name="$1"
    shift
    local args=("$@")

    # Replace $TRY_BIN placeholder with actual binaries
    local args1=("${args[@]/\$TRY_BIN/$BIN1}")
    local args2=("${args[@]/\$TRY_BIN/$BIN2}")

    # Replace $TEST_TRIES placeholder
    args1=("${args1[@]/\$TEST_TRIES/$TEST_TRIES}")
    args2=("${args2[@]/\$TEST_TRIES/$TEST_TRIES}")

    # Run both and capture output
    local out1 out2 exit1 exit2
    out1=$("${args1[@]}" 2>&1) || true
    exit1=$?
    out2=$("${args2[@]}" 2>&1) || true
    exit2=$?

    # Compare outputs (normalize some differences)
    # Remove ANSI codes for comparison
    local norm1 norm2
    norm1=$(echo "$out1" | sed 's/\x1b\[[0-9;]*m//g')
    norm2=$(echo "$out2" | sed 's/\x1b\[[0-9;]*m//g')

    if [ "$norm1" = "$norm2" ] && [ "$exit1" = "$exit2" ]; then
        echo -en "${GREEN}.${NC}"
        TESTS_SAME=$((TESTS_SAME + 1))
    else
        echo ""
        echo -e "${RED}DIFF${NC}: $name"
        echo -e "  ${CYAN}Command:${NC} ${args[*]}"
        if [ "$exit1" != "$exit2" ]; then
            echo -e "  ${YELLOW}Exit codes differ:${NC} A=$exit1 B=$exit2"
        fi
        if [ "$norm1" != "$norm2" ]; then
            echo -e "  ${YELLOW}Output diff:${NC}"
            diff -u <(echo "$out1") <(echo "$out2") | head -20 | sed 's/^/    /'
        fi
        TESTS_DIFF=$((TESTS_DIFF + 1))
    fi
}

# Section header
section() {
    echo -en "\n${YELLOW}$1${NC} "
}

# ═══════════════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════════════

section "basic"

compare_test "--help output" '$TRY_BIN' --help
compare_test "-h output" '$TRY_BIN' -h
compare_test "--version output" '$TRY_BIN' --version
compare_test "-v output" '$TRY_BIN' -v

section "init"

compare_test "init command" '$TRY_BIN' init

section "clone"

compare_test "clone script" '$TRY_BIN' --path='$TEST_TRIES' exec clone https://github.com/user/repo
compare_test "clone with name" '$TRY_BIN' --path='$TEST_TRIES' exec clone https://github.com/user/repo myname

section "selector"

# Note: These tests may differ in exact formatting but should have same essential behavior
compare_test "ESC cancels" '$TRY_BIN' --path='$TEST_TRIES' --and-keys=$'\x1b' exec
compare_test "Enter selects" '$TRY_BIN' --path='$TEST_TRIES' --and-keys=$'\r' exec
compare_test "filter beta" '$TRY_BIN' --path='$TEST_TRIES' --and-keys="beta"$'\r' exec
compare_test "down arrow" '$TRY_BIN' --path='$TEST_TRIES' --and-keys=$'\x1b[B\r' exec

section "tui-render"

compare_test "and-exit render" '$TRY_BIN' --path='$TEST_TRIES' --and-exit exec
compare_test "and-exit with filter" '$TRY_BIN' --path='$TEST_TRIES' --and-exit --and-keys="beta" exec

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Results: $TESTS_SAME same, $TESTS_DIFF different"
if [ $TESTS_DIFF -gt 0 ]; then
    echo -e "${RED}Implementations differ in $TESTS_DIFF tests${NC}"
    exit 1
else
    echo -e "${GREEN}Implementations match!${NC}"
    exit 0
fi
