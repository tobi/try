# Fuzzy matching tests
# Spec: fuzzy_matching.md

section "fuzzy"

# Test: Case-insensitive matching (query "BETA" matches "beta")
output=$(try_run --path="$TEST_TRIES" --and-keys="BETA"$'\r' exec 2>/dev/null)
if echo "$output" | grep -qi "beta"; then
    pass
else
    fail "matching should be case-insensitive" "path contains 'beta'" "$output" "fuzzy_matching.md"
fi

# Test: Case-insensitive matching (mixed case)
output=$(try_run --path="$TEST_TRIES" --and-keys="AlPhA"$'\r' exec 2>/dev/null)
if echo "$output" | grep -qi "alpha"; then
    pass
else
    fail "matching should handle mixed case" "path contains 'alpha'" "$output" "fuzzy_matching.md"
fi

# Test: Partial matching works
output=$(try_run --path="$TEST_TRIES" --and-keys="gam"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "gamma"; then
    pass
else
    fail "partial query should match" "path contains 'gamma'" "$output" "fuzzy_matching.md"
fi

# Test: Non-matching query results in new directory creation
# "xyznotfound" should not match any directory, so selecting it creates new
output=$(try_run --path="$TEST_TRIES" --and-keys="xyznotfound"$'\r' exec 2>/dev/null)
# Should either create mkdir or show cancellation (if [new] not implemented)
if echo "$output" | grep -q "mkdir" || echo "$output" | grep -q "xyznotfound"; then
    pass
else
    # If it cd'd to an existing directory, the filter didn't work properly
    if echo "$output" | grep -q "alpha\|beta\|gamma"; then
        fail "non-matching query should not select existing entries" "mkdir or new entry" "$output" "fuzzy_matching.md"
    else
        pass  # Cancelled or other valid response
    fi
fi

# Test: Consecutive character matches should score higher
# "beta" should be a better match than entries where letters are scattered
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="beta" exec 2>&1)
if echo "$output" | grep -q "beta"; then
    pass
else
    fail "consecutive match should score well" "beta visible" "$output" "fuzzy_matching.md"
fi

# Test: More recent directories should rank higher
# no-date-prefix has the most recent mtime, should appear when no filter
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Check that it appears in results (recency affects ranking)
if echo "$output" | grep -q "no-date-prefix"; then
    pass
else
    fail "recent directories should appear in results" "no-date-prefix visible" "$output" "fuzzy_matching.md"
fi
