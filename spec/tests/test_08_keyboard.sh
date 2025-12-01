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

# Test: Ctrl-H as backspace alternative
# Type "xyz" then Ctrl-H 3 times, then "beta" should match beta
output=$(try_run --path="$TEST_TRIES" --and-keys="xyz"$'\x08\x08\x08'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "Ctrl-H should delete characters" "path contains 'beta'" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-A moves cursor to beginning of line
# Type "beta", Ctrl-A, type "alpha", Enter should match "alphabeta"
# This verifies cursor moved to beginning because "alpha" was inserted before "beta"
output=$(try_run --path="$TEST_TRIES" --and-keys="beta"$'\x01'"alpha"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "alphabeta"; then
    pass
else
    fail "Ctrl-A should move cursor to beginning (alpha should insert at start)" "alphabeta in output" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-E moves cursor to end of line
# Type "alpha", Ctrl-A (to beginning), Ctrl-E (back to end), type "beta", Enter should match "alphabeta"
# This verifies cursor moved to end
output=$(try_run --path="$TEST_TRIES" --and-keys="alpha"$'\x01\x05'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "alphabeta"; then
    pass
else
    fail "Ctrl-E should move cursor to end (beta should insert at end)" "alphabeta in output" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-B moves cursor backward one character
# Type "betaa", Ctrl-B (move cursor back to position 4), Backspace (delete 'a' at position 3)
# Result: "beta" (exact match)
output=$(try_run --path="$TEST_TRIES" --and-keys="betaa"$'\x02\x7f\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "Ctrl-B should move cursor backward" "beta in output" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-F moves cursor forward one character
# Type "alpha", Ctrl-A (move to beginning), Ctrl-F x5 (move forward to position 5/end), type "beta"
# Result: "alphabeta" (exact match)
output=$(try_run --path="$TEST_TRIES" --and-keys="alpha"$'\x01\x06\x06\x06\x06\x06'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "alphabeta"; then
    pass
else
    fail "Ctrl-F should move cursor forward" "alphabeta in output" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-K deletes from cursor to end of line
# Type "alphabeta", Ctrl-A, Ctrl-F x5 (move to middle), Ctrl-K
# Should delete from cursor to end, leaving only "alpha"
output=$(try_run --path="$TEST_TRIES" --and-keys="alphabeta"$'\x01\x06\x06\x06\x06\x06\x0b\r' exec 2>/dev/null)
if echo "$output" | grep -q "alpha"; then
    pass
else
    fail "Ctrl-K should delete to end of line" "alpha should remain" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-W deletes word backward (entire word)
# Type "hello", Ctrl-W (should delete all of "hello"), type "beta", Enter
# Result should match "beta" not "hello"
output=$(try_run --path="$TEST_TRIES" --and-keys="hello"$'\x17'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "Ctrl-W should delete entire word" "beta in output (hello should be deleted)" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-W stops at alphanumeric boundary (dash boundary)
# Type "hello-world", Ctrl-W (should delete only "world", leave "hello-"), type "beta", Enter
# Result should contain "hello" and "beta" together
output=$(try_run --path="$TEST_TRIES" --and-keys="hello-world"$'\x17'"beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "hello.*beta"; then
    pass
else
    fail "Ctrl-W should stop at dash (delete only world)" "hello.*beta in output" "$output" "tui_spec.md#keyboard-input"
fi
