# tmux TUI testing helpers
# Source this file in tests that need real key injection

# Skip if tmux not available
if ! command -v tmux &>/dev/null; then
    echo -e "${YELLOW}SKIP${NC} tmux not installed"
    return 0 2>/dev/null || exit 0
fi

TUI_SESSION="try_test_$$"
TUI_DELAY=0.05
TUI_LAST_OUTPUT=""

# Create session once, reuse for all tests
tmux kill-session -t "$TUI_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TUI_SESSION" -x 80 -y 24
tmux set-option -t "$TUI_SESSION" remain-on-exit on

# Cleanup on exit
trap 'tmux kill-session -t "$TUI_SESSION" 2>/dev/null || true' EXIT

tui_start() {
    # Clear cached output
    TUI_LAST_OUTPUT=""
    # Respawn the pane to clear it
    tmux respawn-pane -t "$TUI_SESSION" -k "$1"
    sleep 0.5  # Let TUI initialize
}

tui_send() {
    tmux send-keys -t "$TUI_SESSION" "$@"
    sleep $TUI_DELAY
    TUI_LAST_OUTPUT=""
}

tui_type() {
    tmux send-keys -t "$TUI_SESSION" -l "$1"
    sleep $TUI_DELAY
    TUI_LAST_OUTPUT=""
}

tui_capture() {
    # Capture visible pane content (no scrollback needed for alternate screen buffer)
    TUI_LAST_OUTPUT=$(tmux capture-pane -t "$TUI_SESSION" -p 2>/dev/null)
    echo "$TUI_LAST_OUTPUT"
}

tui_wait() {
    sleep "${1:-0.5}"
    TUI_LAST_OUTPUT=""
}

_tui_refresh() {
    if [ -z "$TUI_LAST_OUTPUT" ]; then
        TUI_LAST_OUTPUT=$(tmux capture-pane -t "$TUI_SESSION" -p 2>/dev/null)
    fi
}

tui_assert_equals() {
    local expected="$1"
    local msg="${2:-Output should equal expected}"
    _tui_refresh
    if [ "$TUI_LAST_OUTPUT" = "$expected" ]; then
        pass
    else
        fail "$msg" "$expected" "$TUI_LAST_OUTPUT"
    fi
}

tui_assert_substr() {
    local substr="$1"
    local msg="${2:-Output should contain substring}"
    _tui_refresh
    if echo "$TUI_LAST_OUTPUT" | grep -qF "$substr"; then
        pass
    else
        fail "$msg" "$substr" "$TUI_LAST_OUTPUT"
    fi
}

tui_assert_re() {
    local pattern="$1"
    local msg="${2:-Output should match pattern}"
    _tui_refresh
    if echo "$TUI_LAST_OUTPUT" | grep -qE "$pattern"; then
        pass
    else
        fail "$msg" "$pattern" "$TUI_LAST_OUTPUT"
    fi
}

tui_kill() {
    tmux kill-session -t "$TUI_SESSION" 2>/dev/null || true
}
