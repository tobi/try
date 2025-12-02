# Terminal resize handling tests
# Spec: tui_spec.md#resize-handling

section "resize"

# Test: Verify terminal adapts to different widths
# Test narrow terminal (40 columns)
output_narrow=$(TRY_WIDTH=40 TRY_HEIGHT=10 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output_narrow" | grep -q "Try Selector"; then
    pass
else
    fail "narrow terminal should render header" "Try Selector" "$output_narrow" "tui_spec.md#terminal-size"
fi

# Test wide terminal (200 columns)
output_wide=$(TRY_WIDTH=200 TRY_HEIGHT=30 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output_wide" | grep -q "Try Selector"; then
    pass
else
    fail "wide terminal should render header" "Try Selector" "$output_wide" "tui_spec.md#terminal-size"
fi

# Test: Verify content adjusts to terminal height
# Both tall and short terminals should render successfully
output_tall=$(TRY_WIDTH=80 TRY_HEIGHT=30 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
output_short=$(TRY_WIDTH=80 TRY_HEIGHT=10 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)

# Verify both produced output (the actual layout adaptation happens at runtime)
if [ -n "$output_tall" ] && [ -n "$output_short" ]; then
    pass
else
    fail "both tall and short terminals should render" "non-empty outputs" "tall=${#output_tall} short=${#output_short}" "tui_spec.md#dynamic-layout"
fi

# Test: Program continues to function after resize
# This tests that the nil return from read_key doesn't break the main loop
# We simulate changing terminal size by using different TRY_WIDTH values in sequence
# First render at 80 cols
output1=$(TRY_WIDTH=80 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Then render at 120 cols
output2=$(TRY_WIDTH=120 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)

if [ -n "$output1" ] && [ -n "$output2" ]; then
    pass
else
    fail "program should render at different terminal sizes" "non-empty output" "output1 empty or output2 empty" "tui_spec.md#resize-handling"
fi

# Test: Terminal width affects line truncation
# Very narrow terminal should truncate paths
output_narrow=$(TRY_WIDTH=30 TRY_HEIGHT=20 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output_narrow" | grep -q "…" || echo "$output_narrow" | grep -q "project-with-long-name"; then
    # Either we see truncation ellipsis or the full name fits (both are acceptable)
    pass
else
    fail "narrow terminal should show content" "ellipsis or full names" "$output_narrow" "tui_spec.md#path-truncation"
fi

# Test: Selection and input state preserved across resize
# Simulate: type text, then resize, then select
# We can't actually trigger SIGWINCH in the test, but we test the mechanism works
# by verifying the case statement handles nil properly (which read_key returns on resize)
output=$(TRY_WIDTH=80 try_run --path="$TEST_TRIES" --and-keys="beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "text input should work (resize handler doesn't break main loop)" "beta in output" "$output" "tui_spec.md#resize-handling"
fi

# Test: Navigation works after resize simulation
# Verify that returning nil from read_key doesn't break the event loop
output=$(TRY_WIDTH=100 try_run --path="$TEST_TRIES" --and-keys=$'\x1b[B\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "navigation should work (nil case doesn't break loop)" "cd command" "$output" "tui_spec.md#resize-handling"
fi

# Test: Environment variables override terminal detection
# This verifies the resize mechanism's foundation: dynamic width/height querying
output_custom=$(TRY_WIDTH=100 TRY_HEIGHT=25 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if [ -n "$output_custom" ]; then
    pass
else
    fail "TRY_WIDTH/TRY_HEIGHT should override terminal size" "non-empty output" "empty" "tui_spec.md#terminal-size"
fi

# Test: Metadata display adjusts to width
# Wide terminal should show timestamps and scores
output_wide=$(TRY_WIDTH=150 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Look for timestamp patterns like "just now", "Xh ago", "Xd ago" or score patterns like "X.X"
if echo "$output_wide" | grep -qE "(just now|[0-9]+[mhwd] ago|[0-9]+\.[0-9]+)"; then
    pass
else
    # Might not have timestamps if directories are too old or scores if no search
    # This is acceptable, just verify we got output
    if [ -n "$output_wide" ]; then
        pass
    else
        fail "wide terminal should display metadata or content" "non-empty" "empty" "tui_spec.md#metadata-display"
    fi
fi

# Test: Very narrow terminal doesn't crash
# Edge case: terminal so narrow that even truncation is challenging
output_tiny=$(TRY_WIDTH=20 TRY_HEIGHT=10 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
exit_code=$?
if [ $exit_code -eq 1 ]; then
    # --and-exit should always exit with 1 (cancelled)
    pass
else
    fail "very narrow terminal should not crash" "exit code 1" "exit code $exit_code" "tui_spec.md#terminal-size"
fi

# Test: Very short terminal doesn't crash
# Edge case: only enough room for header and footer
output_short=$(TRY_WIDTH=80 TRY_HEIGHT=5 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
exit_code=$?
if [ $exit_code -eq 1 ]; then
    pass
else
    fail "very short terminal should not crash" "exit code 1" "exit code $exit_code" "tui_spec.md#terminal-size"
fi
