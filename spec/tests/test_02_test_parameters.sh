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
