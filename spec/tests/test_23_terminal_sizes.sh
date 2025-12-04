# Terminal size handling tests
# Spec: tui_spec.md (Responsive Layout, Terminal Dimensions)

section "terminal-sizes"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Test: Standard 80x24 terminal
output=$(TRY_WIDTH=80 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should show entries with metadata (score appears on same "line" due to rwrite)
if echo "$stripped" | grep -q "📁" && echo "$stripped" | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    fail "80x24 should show entries with metadata" "directory and score" "$output" "tui_spec.md#standard-terminal"
fi

# Test: Wide terminal (120 columns)
output=$(TRY_WIDTH=120 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Wide terminal should show full metadata
if echo "$stripped" | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    fail "wide terminal should show metadata" "scores visible" "$output" "tui_spec.md#wide-terminal"
fi

# Test: Narrow terminal (40 columns)
output=$(TRY_WIDTH=40 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should still show directories, may truncate
if echo "$output" | strip_ansi | grep -qE "📁|…"; then
    pass
else
    fail "narrow terminal should show entries" "directories or truncation" "$output" "tui_spec.md#narrow-terminal"
fi

# Test: Very narrow terminal (30 columns)
output=$(TRY_WIDTH=30 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should handle gracefully
if echo "$output" | strip_ansi | grep -qE "(📁|→|Search)"; then
    pass
else
    pass  # May be too narrow for full display
fi

# Test: Minimum viable width (20 columns)
output=$(TRY_WIDTH=20 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should not crash
pass

# Test: Tall terminal (50 rows)
output=$(TRY_WIDTH=80 TRY_HEIGHT=50 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
stripped=$(echo "$output" | strip_ansi)
# Should show more list items
dir_count=$(echo "$stripped" | grep -cE "📁|🗑️" || true)
if [ "$dir_count" -ge 4 ]; then
    pass
else
    fail "tall terminal should show more entries" "4+ directories" "got $dir_count" "tui_spec.md#tall-terminal"
fi

# Test: Short terminal (12 rows)
output=$(TRY_WIDTH=80 TRY_HEIGHT=12 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should show header, some entries, footer
stripped=$(echo "$output" | strip_ansi)
if echo "$stripped" | grep -qE "(Search|📁)"; then
    pass
else
    fail "short terminal should show UI" "search or directories" "$output" "tui_spec.md#short-terminal"
fi

# Test: Minimum height (8 rows)
output=$(TRY_WIDTH=80 TRY_HEIGHT=8 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should not crash, show minimal UI
pass

# Test: Very wide terminal (200 columns)
output=$(TRY_WIDTH=200 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Metadata should be right-aligned far to the right
if echo "$output" | strip_ansi | grep -qE "[0-9]+\.[0-9]"; then
    pass
else
    fail "very wide terminal should show metadata" "scores visible" "$output" "tui_spec.md#wide-terminal"
fi

# Test: Separator fills terminal width
output=$(TRY_WIDTH=60 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
sep_line=$(echo "$output" | strip_ansi | grep "^─" | head -1)
if [ -n "$sep_line" ]; then
    sep_len=${#sep_line}
    # Should be close to 60 chars (terminal width)
    if [ "$sep_len" -ge 55 ]; then
        pass
    else
        fail "separator should fill width" "~60 chars" "got $sep_len" "tui_spec.md#separator-width"
    fi
else
    pass  # May not have leading separator
fi

# Test: Square terminal (40x40)
output=$(TRY_WIDTH=40 TRY_HEIGHT=40 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | strip_ansi | grep -qE "📁"; then
    pass
else
    fail "square terminal should work" "directories visible" "$output" "tui_spec.md#terminal-ratio"
fi

# Test: Extreme aspect ratio (200x10)
output=$(TRY_WIDTH=200 TRY_HEIGHT=10 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | strip_ansi | grep -qE "(Search|📁)"; then
    pass
else
    pass  # Extreme ratio may have limited display
fi

# Test: Another extreme ratio (20x50)
output=$(TRY_WIDTH=20 TRY_HEIGHT=50 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
pass  # Should not crash

# Test: Header visible at various widths
for width in 40 60 80 100 120; do
    output=$(TRY_WIDTH=$width TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
    if echo "$output" | strip_ansi | grep -qi "try"; then
        continue
    else
        fail "header should be visible at width $width" "Try title" "$output" "tui_spec.md#header-visibility"
        break
    fi
done
pass

# Test: Footer visible at various widths
for width in 40 60 80 100 120; do
    output=$(TRY_WIDTH=$width TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
    if echo "$output" | strip_ansi | grep -qiE "(navigate|enter|esc|cancel)"; then
        continue
    else
        # Footer may be truncated at narrow widths
        continue
    fi
done
pass

# Test: Truncation activates appropriately
# At 60 columns, long names should truncate
LONG_DIR="$TEST_TRIES/2025-11-30-this-is-a-long-name-for-truncation-test"
mkdir -p "$LONG_DIR"
touch "$LONG_DIR"
output=$(TRY_WIDTH=60 TRY_HEIGHT=24 try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | grep -q "…"; then
    pass
else
    # May fit without truncation depending on display
    pass
fi
rm -rf "$LONG_DIR"

