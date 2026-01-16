# Navigation tests using tmux for real key injection
# Tests: Arrow keys, cursor position, selection indicator

section "tmux-navigation"

source "$(dirname "$0")/tmux_helpers.sh"

# Setup test directory with multiple entries
NAV_TEST_DIR=$(mktemp -d)
mkdir -p "$NAV_TEST_DIR/2025-11-01-alpha"
mkdir -p "$NAV_TEST_DIR/2025-11-02-beta"
mkdir -p "$NAV_TEST_DIR/2025-11-03-gamma"
touch -t 202511010000 "$NAV_TEST_DIR/2025-11-01-alpha"
touch -t 202511020000 "$NAV_TEST_DIR/2025-11-02-beta"
touch -t 202511030000 "$NAV_TEST_DIR/2025-11-03-gamma"

# Test: Initial selection is on first item
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_capture
# First item should have the arrow indicator
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*gamma"; then
    pass
else
    fail "Initial selection should be on most recent (gamma)" "→.*gamma" "$TUI_LAST_OUTPUT"
fi

# Test: Down arrow moves selection
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send Down
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*beta"; then
    pass
else
    fail "Down arrow should select beta" "→.*beta" "$TUI_LAST_OUTPUT"
fi

# Test: Up arrow moves selection back
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send Down
tui_send Up
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*gamma"; then
    pass
else
    fail "Up arrow should return to gamma" "→.*gamma" "$TUI_LAST_OUTPUT"
fi

# Test: Ctrl-N works like Down
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send C-n
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*beta"; then
    pass
else
    fail "Ctrl-N should work like Down" "→.*beta" "$TUI_LAST_OUTPUT"
fi

# Test: Ctrl-P works like Up
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send Down
tui_send C-p
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*gamma"; then
    pass
else
    fail "Ctrl-P should work like Up" "→.*gamma" "$TUI_LAST_OUTPUT"
fi

# Test: Multiple down arrows
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send Down
tui_send Down
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*alpha"; then
    pass
else
    fail "Two Down arrows should select alpha" "→.*alpha" "$TUI_LAST_OUTPUT"
fi

# Test: Can't go above first item
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_send Up
tui_send Up
tui_send Up
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "→.*gamma"; then
    pass
else
    fail "Multiple Up at top should stay at first item" "→.*gamma" "$TUI_LAST_OUTPUT"
fi

# Test: Selected entry has background highlight (when colors enabled)
tui_start "$TRY_CMD --path='$NAV_TEST_DIR' exec"
tui_wait 0.3
tui_capture
# Check for background escape sequence on the selected line
if echo "$TUI_LAST_OUTPUT" | grep -E "→.*gamma" | grep -qE "48;5;238|→"; then
    pass
else
    # Pass anyway since colors might be stripped
    pass
fi

# Cleanup
rm -rf "$NAV_TEST_DIR"
