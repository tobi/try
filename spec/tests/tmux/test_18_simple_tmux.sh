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

tui_assert_substr "Try Selector" "TUI should show header"

# Test: TUI shows directories
tui_assert_substr "alpha" "TUI should show first directory"

# Test: TUI shows Create new entry
tui_assert_substr "Create new" "TUI should show Create new entry"

# Test: TUI shows footer with keybindings
tui_assert_substr "Enter" "TUI should show Enter in footer"

tui_send Down

tui_assert_substr "alpha" "After Down, alpha should still be visible"

tui_send Enter

tui_wait 0.3

tui_assert_substr "cd '$TMUX_TEST_DIR" "Output should show cd command"

# Cleanup
rm -rf "$TMUX_TEST_DIR"
