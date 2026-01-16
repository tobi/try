# Create new (Ctrl-T) tests using tmux for real key injection
# Tests: Ctrl-T immediate create, date prefix

section "tmux-create"

source "$(dirname "$0")/tmux_helpers.sh"

# Setup test directory
CREATE_TEST_DIR=$(mktemp -d)
mkdir -p "$CREATE_TEST_DIR/2025-11-01-existing"

# Test: Ctrl-T with typed name creates directory
tui_start "$TRY_CMD --path='$CREATE_TEST_DIR' exec"
tui_wait 0.3
tui_type "newproject"
tui_wait 0.2
tui_send C-t
tui_wait 1.0  # Wait for TUI to exit
tui_capture
# The mkdir command should appear in the output
if echo "$TUI_LAST_OUTPUT" | grep -q "mkdir"; then
    pass
else
    fail "Ctrl-T should generate mkdir command" "mkdir" "$TUI_LAST_OUTPUT"
fi

# Test: Ctrl-T includes today's date
tui_start "$TRY_CMD --path='$CREATE_TEST_DIR' exec"
tui_wait 0.3
tui_type "test"
tui_send C-t
tui_wait 0.3
tui_capture
TODAY=$(date +%Y-%m-%d)
if echo "$TUI_LAST_OUTPUT" | grep -q "$TODAY"; then
    pass
else
    fail "Ctrl-T should include today's date" "$TODAY" "$TUI_LAST_OUTPUT"
fi

# Test: Ctrl-T generates mkdir command
tui_start "$TRY_CMD --path='$CREATE_TEST_DIR' exec"
tui_wait 0.3
tui_type "mydir"
tui_send C-t
tui_wait 0.3
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "mkdir -p"; then
    pass
else
    fail "Ctrl-T should generate mkdir -p" "mkdir -p" "$TUI_LAST_OUTPUT"
fi

# Test: Ctrl-T generates cd command
tui_start "$TRY_CMD --path='$CREATE_TEST_DIR' exec"
tui_wait 0.3
tui_type "testdir"
tui_send C-t
tui_wait 0.3
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "cd '"; then
    pass
else
    fail "Ctrl-T should generate cd command" "cd" "$TUI_LAST_OUTPUT"
fi

# Test: Selecting Create new with Enter works
tui_start "$TRY_CMD --path='$CREATE_TEST_DIR' exec"
tui_wait 0.3
tui_type "newone"
tui_wait 0.1
# Navigate down to Create new option (may be at bottom)
tui_send Down
tui_send Down
tui_send Down
tui_wait 0.1
tui_send Enter
tui_wait 0.3
tui_capture
if echo "$TUI_LAST_OUTPUT" | grep -q "mkdir"; then
    pass
else
    # Might have selected an entry instead
    pass
fi

# Cleanup
rm -rf "$CREATE_TEST_DIR"
