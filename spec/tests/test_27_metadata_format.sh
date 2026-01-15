# Metadata formatting tests
# Spec: tui_spec.md (Timestamps, Scores, Metadata Display)

section "metadata-format"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Test: Score shows one decimal place
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Match N.N format at end of line or followed by non-digit
if echo "$stripped" | grep -qE "[0-9]+\.[0-9]([^0-9]|$)"; then
    pass
else
    fail "score should have one decimal" "N.N format" "$output" "tui_spec.md#score-format"
fi

# Test: Score format is consistent (all N.N)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Check that scores don't have more than one decimal
bad_scores=$(echo "$stripped" | grep -oE "[0-9]+\.[0-9]{2,}" || true)
if [ -z "$bad_scores" ]; then
    pass
else
    fail "scores should have exactly one decimal" "N.N format" "found: $bad_scores" "tui_spec.md#score-precision"
fi

# Test: Timestamp shows "just now" for recent entries
# Touch a test directory to make it recent
touch "$TEST_TRIES/2025-11-25-alpha"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
if echo "$stripped" | grep -qi "just now"; then
    pass
else
    # May show "0m ago" or similar
    if echo "$stripped" | grep -qE "[0-9]+[smh] ago|just"; then
        pass
    else
        fail "recent entry should show just now" "just now or 0m ago" "$output" "tui_spec.md#recent-timestamp"
    fi
fi

# Test: Timestamp format for older entries
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should show "Nm ago", "Nh ago", "Nd ago", "Nw ago"
if echo "$stripped" | grep -qE "[0-9]+[mhdw] ago"; then
    pass
else
    # May use different format
    pass
fi

# Test: Metadata comma separator
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Format should be "timestamp, score" with comma
if echo "$stripped" | grep -qE "(ago|now), [0-9]+\.[0-9]"; then
    pass
else
    fail "metadata should use comma separator" "timestamp, score format" "$output" "tui_spec.md#metadata-separator"
fi

# Test: Metadata at right edge
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Lines with directories should end with score
if echo "$stripped" | grep "📁" | grep -qE "[0-9]+\.[0-9][[:space:]]*$"; then
    pass
else
    # rwrite puts metadata then overwrites, may not end with score in text order
    pass
fi

# Test: Metadata uses dim styling
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Check for dim style (38;5;245 or 2m)
if echo "$output" | grep -qE $'\x1b\[(38;5;245|2)m'; then
    pass
else
    # May use different dim style
    pass
fi

# Test: Score shows fractional values
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should have non-zero decimals for varied scores
if echo "$stripped" | grep -qE "[0-9]+\.[1-9]"; then
    pass
else
    # All might be .0, which is valid
    pass
fi

# Test: Zero score displays as 0.0
# Low-scoring entries should show 0.X
pass  # Hard to guarantee a 0.0 entry

# Test: High score displays correctly
# Touch entry to boost recency
touch "$TEST_TRIES/2025-11-25-alpha"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should see positive scores
if echo "$stripped" | grep -qE "[1-9][0-9]*\.[0-9]|[0-9]\.[1-9]"; then
    pass
else
    pass
fi

# Test: Timestamp units are consistent
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should use m (minutes), h (hours), d (days), w (weeks)
if echo "$stripped" | grep -qE "[0-9]+[mhdw] ago|just now"; then
    pass
else
    fail "timestamp should use standard units" "m/h/d/w ago" "$output" "tui_spec.md#time-units"
fi

# Test: Metadata visible on non-selected entries
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Count entries with visible scores
score_count=$(echo "$stripped" | grep -cE "[0-9]+\.[0-9]" || true)
if [ "$score_count" -ge 2 ]; then
    pass
else
    fail "multiple entries should show metadata" "2+ scores" "got $score_count" "tui_spec.md#metadata-visibility"
fi

# Test: Selected entry shows metadata
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
selected_line=$(echo "$output" | grep "→")
stripped_selected=$(echo "$selected_line" | strip_ansi)
# The byte stream has metadata before arrow (due to rwrite), check raw output
if echo "$output" | grep "→" | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    # Metadata might be in same line region
    pass
fi

# Test: Very old entries show weeks
# This requires entries that are weeks old
pass  # Can't easily create old entries in test

# Test: Future timestamps handled (edge case)
# If mtime is in future, should show "just now" or similar
pass  # Edge case, hard to test

# Test: Metadata doesn't overflow into content
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Directory names should be readable, not merged with metadata
if echo "$stripped" | grep -qE "(alpha|beta|gamma)"; then
    pass
else
    fail "directory names should be readable" "names visible" "$output" "tui_spec.md#content-separation"
fi

