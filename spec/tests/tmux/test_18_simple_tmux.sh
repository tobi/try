# Simple tmux test - verify TUI renders correctly
# Spec: tui_spec.md

section "tmux-basic"

source "$(dirname "$0")/tmux_helpers.sh"

# Setup test directory
TMUX_TEST_DIR=$(mktemp -d)
mkdir -p "$TMUX_TEST_DIR/2025-11-01-alpha"
mkdir -p "$TMUX_TEST_DIR/2025-11-02-beta"

# Test: TUI shows header
tui_start "$TRY_CMD --path='$TMUX_TEST_DIR' exec"
tui_wait 0.3

tui_assert_substr "Try Directory Selection" "TUI should show header"

# Test: TUI shows directories
tui_assert_substr "alpha" "TUI should show first directory"

# Test: TUI shows footer with keybindings
tui_assert_substr "Enter" "TUI should show Enter in footer"

# Test: Navigation with Down
tui_send Down
tui_wait 0.2
tui_assert_substr "alpha" "After Down, alpha should still be visible"

# Test: Select entry with Enter
tui_send Enter
tui_wait 0.3
tui_assert_substr "cd '$TMUX_TEST_DIR" "Output should show cd command"

# Test: Create new entry appears when typing
tui_start "$TRY_CMD --path='$TMUX_TEST_DIR' exec"
tui_wait 0.3
tui_type "test"
tui_wait 0.2
tui_assert_substr "Create new" "TUI should show Create new entry when searching"

# Cleanup
rm -rf "$TMUX_TEST_DIR"
