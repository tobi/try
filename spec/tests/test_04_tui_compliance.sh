# TUI behavior compliance tests
# Spec: tui_spec.md

section "tui"

# Test: ESC cancels with exit code 1
try_run --path="$TEST_TRIES" --and-keys=$'\x1b' exec >/dev/null 2>&1
exit_code=$?
if [ $exit_code -eq 1 ]; then
    pass
else
    fail "ESC should exit with code 1" "exit code 1" "exit code $exit_code" "tui_spec.md#keyboard-input"
fi

# Test: Enter selects with exit code 0
try_run --path="$TEST_TRIES" --and-keys=$'\r' exec >/dev/null 2>&1
exit_code=$?
if [ $exit_code -eq 0 ]; then
    pass
else
    fail "Enter should exit with code 0" "exit code 0" "exit code $exit_code" "tui_spec.md#keyboard-input"
fi

# Test: Typing filters results
output=$(try_run --path="$TEST_TRIES" --and-keys="beta"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "typing 'beta' should select beta directory" "path contains 'beta'" "$output" "tui_spec.md#text-input"
fi

# Test: Arrow navigation works (down then enter)
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\x1b[B\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "down arrow + enter should select" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Script output format (touch && \ then 2-space indented cd on next line)
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "touch '" && echo "$output" | grep -q "&& \\\\" && echo "$output" | grep -q "^  cd '"; then
    pass
else
    fail "script should chain touch && \\ then indented cd" "touch ... && \\ newline   cd ..." "$output" "command_line.md#script-output-format"
fi

# Test: Script has warning header
if echo "$output" | grep -q "# if you can read this"; then
    pass
else
    fail "script should have warning header" "comment about alias" "$output" "command_line.md#script-output-format"
fi
