# Worktree command tests
# Spec: command_line.md (worktree command)

section "worktree"

# Create a fake git repo for worktree tests
FAKE_REPO=$(mktemp -d)
mkdir -p "$FAKE_REPO/.git"

# Test: worktree with name emits git worktree add
output=$(cd "$FAKE_REPO" && try_run --path="$TEST_TRIES" exec worktree myfeature 2>&1)
if echo "$output" | grep -q "worktree add"; then
    pass
else
    fail "worktree should emit git worktree add" "worktree add command" "$output" "command_line.md#worktree"
fi

# Test: worktree uses date-prefixed name
if echo "$output" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}-myfeature"; then
    pass
else
    fail "worktree should use date-prefixed name" "YYYY-MM-DD-myfeature" "$output" "command_line.md#worktree"
fi

# Test: worktree from non-git dir still creates directory safely
# The worktree add is guarded by rev-parse check so it gracefully skips
PLAIN_DIR=$(mktemp -d)
output=$(cd "$PLAIN_DIR" && try_run --path="$TEST_TRIES" exec worktree plaindir 2>&1)
if echo "$output" | grep -q "mkdir"; then
    pass
else
    fail "worktree from non-git dir should still mkdir" "mkdir command" "$output" "command_line.md#worktree"
fi

# Test: worktree without .git still creates directory
if echo "$output" | grep -q "mkdir"; then
    pass
else
    fail "worktree without .git should still mkdir" "mkdir command" "$output" "command_line.md#worktree"
fi

# Test: dot shorthand (try . <name>) works like worktree
output=$(cd "$FAKE_REPO" && try_run --path="$TEST_TRIES" exec . dotfeature 2>&1)
if echo "$output" | grep -q "worktree add"; then
    pass
else
    fail "try . <name> should emit git worktree add" "worktree add command" "$output" "command_line.md#worktree"
fi

# Test: bare dot (try .) requires name argument
output=$(cd "$FAKE_REPO" && try_run --path="$TEST_TRIES" exec . 2>&1)
if echo "$output" | grep -qi "name"; then
    pass
else
    fail "try . without name should show error" "error about name" "$output" "command_line.md#worktree"
fi

# Cleanup
rm -rf "$FAKE_REPO" "$PLAIN_DIR"
