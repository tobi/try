# Vim-style navigation tests
# Spec: tui_spec.md (Keyboard Input)
# | ↑ / Ctrl-P / Ctrl-K | Move selection up |
# | ↓ / Ctrl-N / Ctrl-J | Move selection down |

section "vim-nav"

# Test: Ctrl-J navigates down (vim-style)
output=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-J,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-J should navigate down" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-K navigates up (vim-style)
output=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-J,CTRL-K,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-K should navigate up" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-N navigates down (emacs-style)
output=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-N,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-N should navigate down" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-P navigates up (emacs-style)
output=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-N,CTRL-P,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-P should navigate up" "cd command" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-J then Ctrl-K returns to same position
first=$(try_run --path="$TEST_TRIES" --and-keys='ENTER' exec 2>/dev/null | grep "^cd '" | head -1)
round_trip=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-J,CTRL-K,ENTER' exec 2>/dev/null | grep "^cd '" | head -1)
if [ "$first" = "$round_trip" ]; then
    pass
else
    fail "Ctrl-J then Ctrl-K should return to same item" "same cd path" "first: $first, round_trip: $round_trip" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-N then Ctrl-P returns to same position
first=$(try_run --path="$TEST_TRIES" --and-keys='ENTER' exec 2>/dev/null | grep "^cd '" | head -1)
round_trip=$(try_run --path="$TEST_TRIES" --and-keys='CTRL-N,CTRL-P,ENTER' exec 2>/dev/null | grep "^cd '" | head -1)
if [ "$first" = "$round_trip" ]; then
    pass
else
    fail "Ctrl-N then Ctrl-P should return to same item" "same cd path" "first: $first, round_trip: $round_trip" "tui_spec.md#keyboard-input"
fi
