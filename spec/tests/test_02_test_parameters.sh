# Test that testing parameters exist (required for spec compliance testing)
# Spec: command_line.md (Testing and Debugging section)

section "test-params"

# Test --and-exit exists (renders TUI once and exits)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if [ -n "$output" ]; then
    pass
else
    fail "--and-exit not working" "TUI output" "empty output" "command_line.md#testing-and-debugging"
fi

# Test --and-keys exists (inject keys)
# ESC should cancel and output "Cancelled."
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x1b' exec 2>/dev/null)
if echo "$output" | grep -qi "cancel"; then
    pass
else
    fail "--and-keys not working (ESC should cancel)" "contains 'cancel'" "$output" "command_line.md#testing-and-debugging"
fi

# Test --and-keys with Enter (should select and output cd script)
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "--and-keys not working (Enter should select)" "contains cd command" "$output" "command_line.md#testing-and-debugging"
fi

# Test TRY_WIDTH environment variable is observed
# With a narrow width (40), the separator should be shorter than with wide width (100)
narrow_output=$(TRY_WIDTH=40 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
wide_output=$(TRY_WIDTH=100 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Count dashes in separator line (─)
narrow_dashes=$(echo "$narrow_output" | grep -o "─" | wc -l)
wide_dashes=$(echo "$wide_output" | grep -o "─" | wc -l)
if [ "$wide_dashes" -gt "$narrow_dashes" ]; then
    pass
else
    fail "TRY_WIDTH should affect separator width" "wide > narrow dashes" "narrow=$narrow_dashes wide=$wide_dashes" "test_spec.md#environment-variables"
fi
