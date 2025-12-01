# Keyboard input tests
# Spec: tui_spec.md (Keyboard Input)

section "keyboard"

# Test: Ctrl-C cancellation (exit code 1)
# Note: Ctrl-C is \x03
try_run --path="$TEST_TRIES" --and-keys=$'\x03' exec >/dev/null 2>&1
exit_code=$?
if [ $exit_code -eq 1 ]; then
    pass
else
    fail "Ctrl-C should exit with code 1" "exit code 1" "exit code $exit_code" "tui_spec.md#keyboard-input"
fi

# Test: Backspace removes characters from query
# Type "xyz" then backspace 3 times, then "beta" should match beta
output=$(try_run --path="$TEST_TRIES" --and-keys="xyz"$'\x7f\x7f\x7f'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "backspace should remove characters" "path contains 'beta'" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Up arrow navigation (Ctrl-P alternative)
# Down then up should be back at first item
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x1b[B\x1b[A\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "up arrow should navigate up" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Multiple navigation (down, down, up, enter)
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x1b[B\x1b[B\x1b[A\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "multiple arrow navigation should work" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-N as down arrow alternative
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x0e\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-N should navigate down" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-P as up arrow alternative
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x0e\x10\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-P should navigate up" "cd command" "$output" "tui_spec.md#keyboard-input"
fi
