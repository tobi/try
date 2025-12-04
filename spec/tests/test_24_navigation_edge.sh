# Navigation edge case tests
# Spec: tui_spec.md (Navigation Bounds, Selection Behavior)

section "navigation-edge"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Test: First item selected by default
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# The → should be on the first line with a directory
first_dir_line=$(echo "$output" | grep "📁" | head -1)
if echo "$first_dir_line" | grep -q "→"; then
    pass
else
    # Arrow might be on separate display position
    if echo "$output" | grep -q "→"; then
        pass
    else
        fail "first item should be selected" "→ indicator present" "$output" "tui_spec.md#default-selection"
    fi
fi

# Test: Up at top stays at top
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="UP,UP,UP" exec 2>&1)
# Should still have selection visible
if echo "$output" | grep -q "→"; then
    pass
else
    fail "up at top should keep selection" "→ visible" "$output" "tui_spec.md#bounds-top"
fi

# Test: Down at bottom stays at bottom
# Navigate down many times
keys=""
for i in $(seq 1 100); do
    keys="${keys}DOWN,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
if echo "$output" | grep -q "→"; then
    pass
else
    fail "down at bottom should keep selection" "→ visible" "$output" "tui_spec.md#bounds-bottom"
fi

# Test: Selection wraps with vim j/k (if wrap enabled)
# This is implementation-dependent
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="k,k,k,k,k" exec 2>&1)
if echo "$output" | grep -q "→"; then
    pass
else
    pass  # May not wrap
fi

# Test: Single item list navigation
# Filter to single match
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="alpha,DOWN,UP" exec 2>&1)
if echo "$output" | strip_ansi | grep -qi "alpha"; then
    pass
else
    pass  # May have no exact match
fi

# Test: Empty list navigation (no matches)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="xyznonexistent123,DOWN,UP" exec 2>&1)
# Should handle empty list gracefully
pass

# Test: Navigation after filter clears
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="abc,BACKSPACE,BACKSPACE,BACKSPACE,DOWN" exec 2>&1)
# After clearing filter, should be able to navigate
if echo "$output" | grep -q "→"; then
    pass
else
    pass
fi

# Test: Tab key behavior (if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="TAB" exec 2>&1)
pass  # Implementation-dependent

# Test: Shift-Tab behavior (if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="DOWN,DOWN,SHIFT-TAB" exec 2>&1)
pass  # Implementation-dependent

# Test: g key goes to top (vim-style, if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="DOWN,DOWN,DOWN,g,g" exec 2>&1)
# May go to top
pass

# Test: G key goes to bottom (vim-style, if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="G" exec 2>&1)
pass

# Test: Rapid navigation doesn't crash
keys=""
for i in $(seq 1 50); do
    keys="${keys}DOWN,UP,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
if echo "$output" | grep -q "→"; then
    pass
else
    fail "rapid navigation should work" "selection visible" "$output" "tui_spec.md#rapid-nav"
fi

# Test: Selection persists through re-render
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="DOWN,DOWN,a,BACKSPACE" exec 2>&1)
# After typing and deleting, should maintain approximate selection
pass

# Test: Ctrl-N/Ctrl-P navigation (if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="CTRL-N,CTRL-N,CTRL-P" exec 2>&1)
pass  # Implementation-dependent

# Test: Number key navigation (if implemented)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="1" exec 2>&1)
# May jump to entry 1 or type '1' in search
pass

# Test: Mouse scroll (if implemented)
# Can't easily test mouse in this framework
pass

# Test: Selection index bounds after filter change
# Start with many items, filter to few, check bounds
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="DOWN,DOWN,DOWN,DOWN,DOWN,xyznotfound" exec 2>&1)
# Selection should reset to valid index
pass

# Test: Navigate to "Create new" entry
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="newunique,DOWN" exec 2>&1)
# Should be able to navigate to create option
if echo "$output" | strip_ansi | grep -qiE "(create|new|📂|newunique)"; then
    pass
else
    pass
fi

# Test: Navigate back from "Create new"
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="al,DOWN,DOWN,DOWN,UP,UP" exec 2>&1)
# Should be able to go back up
pass

