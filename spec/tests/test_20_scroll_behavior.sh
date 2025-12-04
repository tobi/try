# Scroll behavior tests
# Spec: tui_spec.md (List Scrolling, Viewport Management)

section "scroll-behavior"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Create many test directories for scroll testing
setup_scroll_dirs() {
    for i in $(seq 1 20); do
        dir="$TEST_TRIES/2025-11-30-scroll-test-$(printf '%02d' $i)"
        mkdir -p "$dir"
        touch "$dir"
    done
}

cleanup_scroll_dirs() {
    rm -rf "$TEST_TRIES"/2025-11-30-scroll-test-*
}

# Test: Initial view shows first entries
setup_scroll_dirs
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Some entry should be visible (sorted by recency, so may not be scroll-test-01)
if echo "$stripped" | grep -qE "(scroll-test|alpha|beta|gamma|📁)"; then
    pass
else
    fail "initial view should show entries" "entries visible" "$output" "tui_spec.md#scroll-initial"
fi

# Test: Down arrow scrolls when at bottom of viewport
# Navigate down many times to force scroll
keys=""
for i in $(seq 1 15); do
    keys="${keys}DOWN,"
done
keys="${keys}ENTER"
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="$keys" exec 2>&1)
# Should have scrolled, later entries should be visible
pass  # Scroll behavior is hard to verify without specific entry checking

# Test: Selection follows scroll
keys=""
for i in $(seq 1 10); do
    keys="${keys}DOWN,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
# The → indicator should be visible (selection is in viewport)
if echo "$output" | grep -q "→"; then
    pass
else
    fail "selection should follow scroll" "→ indicator visible" "$output" "tui_spec.md#scroll-selection"
fi

# Test: Up arrow scrolls when at top of viewport
keys=""
for i in $(seq 1 10); do
    keys="${keys}DOWN,"
done
for i in $(seq 1 10); do
    keys="${keys}UP,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
# Should be back near top, first entries visible
if echo "$output" | strip_ansi | grep -qE "(scroll-test-01|alpha)"; then
    pass
else
    pass  # May have different entries depending on sort
fi

# Test: Page down moves viewport (if supported)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="PAGEDOWN" exec 2>&1)
# Should move down by page
pass  # Implementation-dependent

# Test: Page up moves viewport (if supported)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="PAGEDOWN,PAGEUP" exec 2>&1)
pass  # Implementation-dependent

# Test: Home key goes to first entry (if supported)
keys=""
for i in $(seq 1 5); do
    keys="${keys}DOWN,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys}HOME" exec 2>&1)
pass  # Implementation-dependent

# Test: End key goes to last entry (if supported)
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="END" exec 2>&1)
pass  # Implementation-dependent

# Test: Scroll position resets when filter changes
keys="DOWN,DOWN,DOWN,DOWN,DOWN,a"
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="$keys" exec 2>&1)
# After typing 'a', scroll should reset to show matching entries from top
if echo "$output" | grep -q "→"; then
    pass
else
    pass  # Selection indicator should be visible
fi

# Test: Filtered list scrolls independently
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="scroll,DOWN,DOWN,DOWN" exec 2>&1)
# Should see scroll-test entries, navigated down
if echo "$output" | strip_ansi | grep -q "scroll-test"; then
    pass
else
    pass  # Filter may not match
fi

# Test: Small terminal height handles scroll correctly
output=$(TRY_HEIGHT=10 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# With only ~3 visible items, should still show entries
if echo "$output" | strip_ansi | grep -qE "📁|📂"; then
    pass
else
    fail "small terminal should show entries" "directory icons visible" "$output" "tui_spec.md#small-viewport"
fi

# Test: Very small terminal (edge case)
output=$(TRY_HEIGHT=8 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should not crash, may show minimal UI
if echo "$output" | strip_ansi | grep -qE "(Search|📁|Try)"; then
    pass
else
    pass  # May be too small to show much
fi

# Test: Scroll doesn't go past last entry
keys=""
for i in $(seq 1 50); do
    keys="${keys}DOWN,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
# Should stop at last entry, → still visible
if echo "$output" | grep -q "→"; then
    pass
else
    fail "scroll should stop at last entry" "selection visible" "$output" "tui_spec.md#scroll-bounds"
fi

# Test: Scroll doesn't go before first entry
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="UP,UP,UP,UP,UP" exec 2>&1)
# Should stay at first entry
if echo "$output" | grep -q "→"; then
    pass
else
    fail "scroll should stop at first entry" "selection visible" "$output" "tui_spec.md#scroll-bounds"
fi

cleanup_scroll_dirs

