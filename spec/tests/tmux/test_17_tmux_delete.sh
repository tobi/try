# Delete mode tests using tmux for real key injection
# Spec: delete_spec.md

section "tmux-delete"

# Load tmux helpers
source "$(dirname "$0")/tmux_helpers.sh"

# --- Tests ---

# Setup test directories
TMUX_TEST_DIR=$(mktemp -d)
mkdir -p "$TMUX_TEST_DIR/2025-11-01-first"
mkdir -p "$TMUX_TEST_DIR/2025-11-02-second"

# Test: Delete mode shows DELETE MODE in footer
tui_start "$TRY_CMD --path='$TMUX_TEST_DIR' exec"
tui_send C-d
tui_wait 0.2
tui_assert_re "DELETE" "Ctrl-D should show DELETE MODE"

# Test: Full delete flow with tmux
# Recreate test dirs (may have been deleted by previous test)
mkdir -p "$TMUX_TEST_DIR/2025-11-01-first"
mkdir -p "$TMUX_TEST_DIR/2025-11-02-second"
tui_start "$TRY_CMD --path='$TMUX_TEST_DIR' exec"
tui_send C-d
tui_send Enter
tui_type "YES"
tui_send Enter
tui_wait 0.3
tui_assert_substr "rm -rf" "Full delete flow should generate rm -rf"

# Cleanup
rm -rf "$TMUX_TEST_DIR"
