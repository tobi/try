#!/bin/bash
# Standalone tmux test runner
# Usage: ./run.sh /path/to/try

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/try"
    exit 1
fi

TRY_CMD="$1"

# Convert to absolute path
if [[ "$TRY_CMD" != /* ]]; then
    TRY_CMD="$(cd "$(dirname "$TRY_CMD")" && pwd)/$(basename "$TRY_CMD")"
fi

if [ ! -x "$TRY_CMD" ]; then
    echo -e "${RED}Error: '$TRY_CMD' is not executable${NC}"
    exit 1
fi

export TRY_CMD

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -en "${GREEN}.${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
    echo -e "\n${RED}FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo "  Expected: $2"
    fi
    if [ -n "$3" ]; then
        echo -e "\n  Command output:\n\n$3\n"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

section() {
    echo -en "\n${YELLOW}$1${NC} "
}

export -f pass fail section

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run tests
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    source "$test_file"
done

# Summary
echo -e "\n\n═══════════════════════════════════"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}$TESTS_FAILED tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed${NC}"
fi
