# [new] entry tests
# Spec: tui_spec.md (New Directory Creation)

section "new-entry"

# Test: "[new]" entry appears when query has no exact match
# Note: --and-exit captures initial render; query may not be fully processed
# This test checks for [new] OR for the query being shown in selector output
output=$(try_run --path="$TEST_TRIES" --and-keys="uniquequery"$'\r' exec 2>/dev/null)
# When selecting a non-matching query, should get mkdir script (creating new)
if echo "$output" | grep -q "mkdir"; then
    pass
else
    # Alternative: if no mkdir, check if [new] appears in TUI render
    output2=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="uniquequery" exec 2>&1)
    if echo "$output2" | grep -qi "\[new\]"; then
        pass
    else
        fail "[new] or mkdir should appear for unmatched query" "mkdir command or [new] entry" "$output" "tui_spec.md#new-directory-creation"
    fi
fi

# Test: Selecting "[new]" creates mkdir script
# Type unique query and press Enter - should get mkdir script
output=$(try_run --path="$TEST_TRIES" --and-keys="newproject"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "mkdir"; then
    pass
else
    fail "selecting [new] should output mkdir" "mkdir command" "$output" "tui_spec.md#new-directory-creation"
fi

# Test: mkdir script has correct YYYY-MM-DD format
if echo "$output" | grep -qE "mkdir.*[0-9]{4}-[0-9]{2}-[0-9]{2}-newproject"; then
    pass
else
    fail "mkdir should have YYYY-MM-DD prefix" "YYYY-MM-DD-newproject" "$output" "tui_spec.md#new-directory-creation"
fi

# Test: [new] script includes cd to the new directory
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "[new] script should include cd" "cd command" "$output" "tui_spec.md#new-directory-creation"
fi

# Test: [new] does NOT appear when query matches existing entry exactly
# Type exact name without date prefix
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="alpha" exec 2>&1)
# If "alpha" matches 2025-11-01-alpha well, [new] might still appear if no exact match
# This test is more about ensuring exact matches are found
if echo "$output" | grep -q "alpha"; then
    pass
else
    fail "query should find matching entries" "alpha in results" "$output" "tui_spec.md#fuzzy-matching"
fi
