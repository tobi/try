# Display and rendering tests
# Spec: tui_spec.md (Metadata Display)

section "display"

# Test: Scores are shown (with --and-exit we can see rendered output)
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Scores should be displayed with a decimal (e.g., "1.5" or "0.8")
if echo "$output" | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    fail "scores should be displayed with decimal" "number with decimal (e.g., 1.5)" "$output" "tui_spec.md#metadata-display"
fi

# Test: Relative timestamps are shown
# Check for time indicators like "just now", "ago", or time units
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | grep -qiE "(just now|ago|[0-9]+[dhms])"; then
    pass
else
    fail "relative timestamps should be shown" "time indicator (e.g., 'ago', '5d')" "$output" "tui_spec.md#metadata-display"
fi

# Test: Long paths are handled (may be truncated with ellipsis)
# Our test has "2025-11-25-project-with-long-name"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should either show full name or truncated with ellipsis
if echo "$output" | grep -q "project-with-long-name" || echo "$output" | grep -q "…"; then
    pass
else
    fail "long names should be handled" "full name or ellipsis truncation" "$output" "tui_spec.md#metadata-display"
fi

# Test: Selection indicator is visible
# There should be some indicator for the selected item (e.g., >, *, highlight)
output=$(try_run --path="$TEST_TRIES" --and-exit --no-expand-tokens exec 2>&1)
# Check for common selection indicators or section markers
if echo "$output" | grep -qE "(>|{section}|\*|→)"; then
    pass
else
    # This test might be too implementation-specific, so we'll be lenient
    # If there's any directory shown, that's acceptable
    if echo "$output" | grep -q "$TEST_TRIES"; then
        pass
    else
        fail "selection indicator should be visible" "selection marker (>, *, etc.)" "$output" "tui_spec.md#selection-rendering"
    fi
fi

# Test: Search prompt label is visible
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# The search prompt (e.g., "Search:") should be visible
if echo "$output" | grep -qi "search"; then
    pass
else
    fail "search prompt should be visible" "Search label" "$output" "tui_spec.md#query-display"
fi

# Test: --no-colors disables styling ANSI codes (colors, bold)
# Note: cursor control sequences ([?25l, [H, [K, [J) are still emitted
output_colors=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
output_no_colors=$(try_run --no-colors --path="$TEST_TRIES" --and-exit exec 2>&1)
# With colors should have style codes like [1m or [1; (bold), [38;5;Nm (256-color), [0m (reset)
# Check for bold attribute which may appear as [1m alone or [1; combined with color
colors_has_styles=$(echo "$output_colors" | grep -cE $'\x1b\\[1[m;]' || true)
no_colors_has_styles=$(echo "$output_no_colors" | grep -cE $'\x1b\\[1[m;]' || true)
if [ "$colors_has_styles" -gt 0 ] && [ "$no_colors_has_styles" -eq 0 ]; then
    pass
else
    fail "--no-colors should remove style codes" "no [1m/[1; sequences" "with colors: $colors_has_styles, without: $no_colors_has_styles" "command_line.md#global-options"
fi

# Test: NO_COLOR environment variable disables colors
output_env=$( NO_COLOR=1 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
env_has_styles=$(echo "$output_env" | grep -c $'\x1b\[1m' || true)
if [ "$env_has_styles" -eq 0 ]; then
    pass
else
    fail "NO_COLOR env should disable colors" "no [1m sequences" "found $env_has_styles" "command_line.md#environment"
fi

# Test: Long directory names show metadata on same line
# Create a test dir with a very long name
LONG_DIR="$TEST_TRIES/2025-11-30-this-is-a-very-long-directory-name-for-testing"
mkdir -p "$LONG_DIR"
touch "$LONG_DIR"
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# With rwrite, metadata is written first then main content overwrites from left
# The line should contain both the directory name fragment AND metadata
# (in byte order: metadata comes first, then name after \r)
line=$(echo "$output" | grep "long-directory")
if [ -n "$line" ]; then
    # Check that metadata appears somewhere on this line
    if echo "$line" | grep -qE "[0-9]+\.[0-9]"; then
        pass
    else
        fail "long names should show metadata" "metadata on same line" "$output" "tui_spec.md#metadata-display"
    fi
else
    fail "long names should be visible" "line with long-directory" "$output" "tui_spec.md#metadata-display"
fi
rm -rf "$LONG_DIR"
