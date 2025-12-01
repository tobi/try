# Basic compliance tests: --help, --version
# Spec: command_line.md (Global Options)

section "basic"

# Test --help
output=$(try_run --help 2>&1)
if echo "$output" | grep -q "ephemeral workspace manager"; then
    pass
else
    fail "--help missing expected text" "contains 'ephemeral workspace manager'" "$output" "command_line.md"
fi

# Test -h
output=$(try_run -h 2>&1)
if echo "$output" | grep -q "ephemeral workspace manager"; then
    pass
else
    fail "-h missing expected text" "contains 'ephemeral workspace manager'" "$output" "command_line.md"
fi

# Test --version
output=$(try_run --version 2>&1)
if echo "$output" | grep -qE "^try [0-9]+\.[0-9]+"; then
    pass
else
    fail "--version format incorrect" "try X.Y.Z" "$output" "command_line.md"
fi

# Test -v
output=$(try_run -v 2>&1)
if echo "$output" | grep -qE "^try [0-9]+\.[0-9]+"; then
    pass
else
    fail "-v format incorrect" "try X.Y.Z" "$output" "command_line.md"
fi

# Test unknown argument is treated as search query (opens TUI)
# This matches "try [query]" behavior - any non-command is a search term
output=$(try_run --and-exit unknownquery 2>&1)
if echo "$output" | grep -qi "selector\|search\|cancelled"; then
    pass
else
    fail "unknown arg should open TUI as search query" "TUI output or Cancelled" "$output" "command_line.md"
fi
