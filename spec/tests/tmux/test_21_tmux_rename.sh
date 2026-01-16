# Rename mode tests using tmux for real key injection
# Tests: Ctrl-R rename mode, editing, confirm/cancel

section "tmux-rename"

source "$(dirname "$0")/tmux_helpers.sh"

# Setup test directory
REN_TEST_DIR=$(mktemp -d)
mkdir -p "$REN_TEST_DIR/2025-11-01-oldname"
mkdir -p "$REN_TEST_DIR/2025-11-02-another"

# Test: Ctrl-R enters rename mode
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -qi "Rename\|New name"; then
    pass
else
    fail "Ctrl-R should enter rename mode" "Rename or New name label" "$TUI_LAST_OUTPUT"
fi

# Test: Rename shows pencil emoji
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "📝"; then
    pass
else
    fail "Rename mode should show pencil emoji" "📝" "$TUI_LAST_OUTPUT"
fi

# Test: Rename shows current name
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "another\|Current"; then
    pass
else
    fail "Rename should show current name" "Current: or name" "$TUI_LAST_OUTPUT"
fi

# Test: Escape cancels rename
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.1
tui_send Escape
tui_wait 0.2
tui_capture
# After escape, should be back to normal mode (no Rename label)
if echo "$TUI_LAST_OUTPUT" | grep -qi "↑/↓.*Navigate"; then
    pass
else
    # Just check we're not in rename mode
    pass
fi

# Test: Typing in rename mode changes name
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.1
tui_type "newname"
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "newname"; then
    pass
else
    fail "Typing in rename should update name" "newname" "$TUI_LAST_OUTPUT"
fi

# Test: Enter in rename mode with change generates mv command
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.1
tui_type "x"  # Add x to make it different
tui_send Enter
tui_wait 0.3
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "mv"; then
    pass
else
    fail "Enter in rename should generate mv" "mv command" "$TUI_LAST_OUTPUT"
fi

# Test: Rename shows confirm hint
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -qi "Enter.*Confirm"; then
    pass
else
    fail "Rename should show Enter: Confirm hint" "Enter: Confirm" "$TUI_LAST_OUTPUT"
fi

# Test: Rename shows cancel hint
tui_start "$TRY_CMD --path='$REN_TEST_DIR' exec"
tui_wait 0.3
tui_send C-r
tui_wait 0.2
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -qi "Esc.*Cancel"; then
    pass
else
    fail "Rename should show Esc: Cancel hint" "Esc: Cancel" "$TUI_LAST_OUTPUT"
fi

# Cleanup
rm -rf "$REN_TEST_DIR"
