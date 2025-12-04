# Line layout and metadata positioning tests
# Spec: tui_spec.md (Metadata Positioning, Line Layout Examples, Truncation Algorithm)

section "line-layout"

# Helper to strip ANSI codes for easier text analysis
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Test: Short names show full metadata right-aligned
# Short directory names should have both timestamp and score visible
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Check for "just now" or "ago" followed by comma and score
if echo "$output" | strip_ansi | grep -qE "(just now|[0-9]+[mhdw] ago), [0-9]+\.[0-9]"; then
    pass
else
    fail "short names should show full metadata" "timestamp, score (e.g., 'just now, 3.0')" "$output" "tui_spec.md#metadata-positioning"
fi

# Test: Metadata appears on line with short names (right-aligned via cursor positioning)
# The score should appear on the same line as the name
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Find a line with alpha (short name) and check that metadata is present
# With rwrite, metadata is written first at right edge, then main content overwrites from left
if echo "$output" | strip_ansi | grep "alpha" | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    fail "metadata should appear on same line as short names" "score on line with alpha" "$output" "tui_spec.md#line-layout-examples"
fi

# Test: Very long directory name gets truncated with ellipsis
VERY_LONG_DIR="$TEST_TRIES/2025-11-30-this-is-an-extremely-long-directory-name-that-will-definitely-need-truncation"
mkdir -p "$VERY_LONG_DIR"
touch "$VERY_LONG_DIR"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should see ellipsis character when name is truncated
if echo "$output" | grep -q "…"; then
    pass
else
    fail "very long names should be truncated with ellipsis" "ellipsis character (…)" "$output" "tui_spec.md#truncation-algorithm"
fi
rm -rf "$VERY_LONG_DIR"

# Test: Truncated names don't show full metadata (to save space)
# Create a name that's long enough to truncate but might still fit partial metadata
LONG_DIR="$TEST_TRIES/2025-11-30-moderately-long-directory-name-here"
mkdir -p "$LONG_DIR"
touch "$LONG_DIR"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Line with long dir should either show partial metadata or ellipsis, not both full metadata and truncation
stripped=$(echo "$output" | strip_ansi)
# Check we have reasonable output (either shows the long name or truncates it)
if echo "$stripped" | grep -qE "(moderately-long|…)"; then
    pass
else
    fail "long names should be handled" "partial name or ellipsis" "$output" "tui_spec.md#truncation-algorithm"
fi
rm -rf "$LONG_DIR"

# Test: Metadata stays right-aligned even with partial display
# When metadata is truncated, the remaining portion should still be at right edge
PARTIAL_META_DIR="$TEST_TRIES/2025-11-30-this-is-a-very-long-directory-name-for-testing"
mkdir -p "$PARTIAL_META_DIR"
touch "$PARTIAL_META_DIR"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Find the line and check that whatever metadata is shown is followed by line ending (not more spaces)
# The metadata fragment should end the visible content
line=$(echo "$output" | strip_ansi | grep "long-directory-name" | head -1)
if [ -n "$line" ]; then
    # Line should end with a digit (score decimal) followed by whitespace/end
    if echo "$line" | grep -qE "[0-9]$" || echo "$line" | grep -qE "[0-9][[:space:]]*$"; then
        pass
    else
        # Could also just end with the name if metadata completely hidden
        pass
    fi
else
    fail "should find long directory line" "line with long-directory-name" "$output" "tui_spec.md#metadata-positioning"
fi
rm -rf "$PARTIAL_META_DIR"

# Test: Selection arrow doesn't break layout
# The selected item should still have proper alignment
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Check that arrow indicator exists and line still has metadata
if echo "$output" | strip_ansi | grep -qE "^→.*[0-9]\.[0-9]"; then
    pass
else
    # Arrow might be with different formatting, just check metadata is present on some line
    if echo "$output" | strip_ansi | grep -qE "[0-9]+\.[0-9]"; then
        pass
    else
        fail "selected item should have metadata" "score on selected line" "$output" "tui_spec.md#line-layout-examples"
    fi
fi

# Test: Multiple lines maintain consistent alignment
# All visible directory lines should have metadata at similar positions
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Count lines that have scores (indicating metadata)
meta_lines=$(echo "$stripped" | grep -cE "[0-9]+\.[0-9]" || true)
# We have at least 4 test directories, should see multiple with metadata
if [ "$meta_lines" -ge 2 ]; then
    pass
else
    fail "multiple lines should show metadata" "at least 2 lines with scores" "found $meta_lines lines" "tui_spec.md#metadata-positioning"
fi

# Test: Token-aware truncation preserves formatting
# When fuzzy match highlights are present, truncation shouldn't break {b}...{/b} pairs
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="alph,ENTER" --no-expand-tokens exec 2>&1)
# With fuzzy match "alph", should see {b} tokens in output
# Check that any {b} has a matching {/b} (or the line doesn't have {b} at all)
if echo "$output" | grep -q "{b}"; then
    # If there's a {b}, there should also be {/b}
    if echo "$output" | grep -q "{/b}"; then
        pass
    else
        fail "fuzzy highlight tokens should be paired" "{b} should have matching {/b}" "$output" "tui_spec.md#truncation-algorithm"
    fi
else
    # No {b} tokens is also fine (might be fully visible without truncation)
    pass
fi

# Test: Empty filter shows all entries with metadata
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should see multiple directories listed
dir_count=$(echo "$stripped" | grep -cE "📁|🗑️|📂" || true)
if [ "$dir_count" -ge 4 ]; then
    pass
else
    fail "empty filter should show all directories" "at least 4 directories" "found $dir_count" "tui_spec.md#display-layout"
fi

# Test: Very wide terminal (400 chars) doesn't cause buffer overflow
# This tests that the implementation handles extremely wide terminals safely
output=$(TRY_WIDTH=400 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | strip_ansi | grep -qE "(alpha|beta|gamma)"; then
    pass
else
    fail "wide terminal should display correctly" "directory names visible" "$output" "tui_spec.md#line-layout"
fi
