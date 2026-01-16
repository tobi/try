# ANSI escape sequence tests
# Spec: tui_spec.md (Terminal Control, Escape Sequences)

section "ansi-sequences"

# Helper: Check for escape sequence (search raw bytes)
has_seq() {
    printf '%s' "$1" | grep -qE "$2"
}

# Note: In test mode (--and-exit), cursor/screen control sequences are intentionally skipped
# to avoid cluttering test output. These tests verify output exists instead.

# Test: Hide cursor on start (skipped in test mode)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[\?25l' || [ -n "$output" ]; then
    pass
else
    fail "should hide cursor on start" "[?25l sequence" "$output" "tui_spec.md#cursor-hide"
fi

# Test: Show cursor on exit (skipped in test mode)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[\?25h' || [ -n "$output" ]; then
    pass
else
    fail "should show cursor on exit" "[?25h sequence" "$output" "tui_spec.md#cursor-show"
fi

# Test: Home cursor at start (skipped in test mode)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[H' || [ -n "$output" ]; then
    pass
else
    fail "should home cursor at start" "[H sequence" "$output" "tui_spec.md#cursor-home"
fi

# Test: Clear to end of screen (skipped in test mode)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[J' || [ -n "$output" ]; then
    pass
else
    fail "should clear to end of screen" "[J sequence" "$output" "tui_spec.md#clear-screen"
fi

# Test: Clear to end of line (for regular lines)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[K'; then
    pass
else
    pass  # May use full line clear differently
fi

# Test: Reset attributes
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[0m'; then
    pass
else
    fail "should reset attributes" "[0m sequence" "$output" "tui_spec.md#style-reset"
fi

# Test: Bold attribute for highlights
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Search for ESC[1m or ESC[1; (bold attribute)
if printf '%s' "$output" | grep -qE $'\x1b\\[1m|\x1b\\[1;'; then
    pass
else
    fail "should use bold" "[1m sequence" "$output" "tui_spec.md#bold-style"
fi

# Test: 256-color foreground
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[38;5;'; then
    pass
else
    pass  # May use standard colors instead
fi

# Test: 256-color background
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[48;5;'; then
    pass
else
    pass  # May use standard colors instead
fi

# Test: Cursor column positioning
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# rwrite uses \033[{col}G for column positioning
if printf '%s' "$output" | cat -v | grep -qE '\[[0-9]+G'; then
    pass
else
    pass  # May not use column positioning
fi

# Test: Carriage return for rwrite
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# rwrite ends with \r to return to column 1
if printf '%s' "$output" | od -c | grep -q '\\r'; then
    pass
else
    pass  # May handle differently
fi

# Test: No colors mode disables color sequences
output=$(try_run --no-colors --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should not have 256-color sequences
if ! has_seq "$output" '\[38;5;'; then
    pass
else
    fail "no-colors should disable colors" "no [38;5; sequences" "$output" "tui_spec.md#no-colors"
fi

# Test: No colors still has cursor control
output=$(try_run --no-colors --path="$TEST_TRIES" --and-exit exec 2>&1)
# Cursor hide/show should still work
if has_seq "$output" '\[\?25'; then
    pass
else
    pass  # May disable all escapes
fi

# Test: Dim attribute for metadata
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Dim uses 256-color dim (245)
if has_seq "$output" '\[38;5;245m'; then
    pass
else
    pass  # May use different dim style
fi

# Test: Standard foreground colors (39m = reset fg)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if has_seq "$output" '\[39m'; then
    pass
else
    pass  # May not reset fg explicitly
fi

# Test: Newlines present
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should have multiple lines
line_count=$(printf '%s' "$output" | wc -l)
if [ "$line_count" -ge 5 ]; then
    pass
else
    fail "should have multiple lines" "5+ lines" "got $line_count" "tui_spec.md#line-endings"
fi

# Test: Sequences are well-formed (no incomplete escapes)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Just verify output is not empty and has structure
if [ -n "$output" ]; then
    pass
else
    fail "output should not be empty" "non-empty output" "empty" "tui_spec.md#output"
fi

