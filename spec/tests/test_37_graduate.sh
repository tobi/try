# Graduate (ascend) tests
# Verify Ctrl-G promotes a try to a project directory

section "graduate"

GRAD_DIR=$(mktemp -d)
PROJ_DIR=$(mktemp -d)
mkdir -p "$GRAD_DIR/2025-06-01-my-experiment"
touch -t 202506010000 "$GRAD_DIR/2025-06-01-my-experiment"

# Test: Ctrl-G then ESC cancels without graduating
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ESC' exec 2>/dev/null)
if echo "$output" | grep -q "mv "; then
    fail "Ctrl-G then Esc should cancel" "no mv" "$output" "graduate"
else
    pass
fi

# Test: Ctrl-G then Enter generates move script
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "mv "; then
    pass
else
    fail "Ctrl-G then Enter should generate move script" "mv command" "$output" "graduate"
fi

# Test: Graduate script creates a symlink
if echo "$output" | grep -q "ln -s "; then
    pass
else
    fail "Graduate script should create symlink" "ln -s" "$output" "graduate"
fi

# Test: Graduate script includes cd to destination
if echo "$output" | grep -q "cd "; then
    pass
else
    fail "Graduate script should cd to destination" "cd" "$output" "graduate"
fi

# Test: Graduate strips date prefix from destination name
if echo "$output" | grep "mv " | grep -q "my-experiment"; then
    pass
else
    fail "Graduate should strip date prefix" "my-experiment in destination" "$output" "graduate"
fi

# Test: Graduate script includes echo with graduation message
if echo "$output" | grep -q "Graduated:"; then
    pass
else
    fail "Graduate script should show graduation message" "Graduated:" "$output" "graduate"
fi

# Test: TRY_PROJECTS overrides destination directory
output=$(TRY_PROJECTS="$PROJ_DIR" try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "$PROJ_DIR"; then
    pass
else
    fail "TRY_PROJECTS should override destination" "$PROJ_DIR in output" "$output" "graduate"
fi

# Test: Default destination uses parent of TRY_PATH
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
parent_dir=$(dirname "$GRAD_DIR")
if echo "$output" | grep -q "$parent_dir"; then
    pass
else
    fail "Default destination should use parent of tries path" "$parent_dir in output" "$output" "graduate"
fi

# Test: Ctrl-G on entry without date prefix keeps full name
NO_DATE_DIR=$(mktemp -d)
mkdir -p "$NO_DATE_DIR/plain-project"
output=$(try_run --path="$NO_DATE_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep "mv " | grep -q "plain-project"; then
    pass
else
    fail "Entry without date prefix should keep full name" "plain-project" "$output" "graduate"
fi

# Test: Graduate with git worktree uses git worktree move
WT_DIR=$(mktemp -d)
mkdir -p "$WT_DIR/2025-06-01-worktree-test"
# Create a .git file (marks it as a worktree)
echo "gitdir: /tmp/fake-repo/.git/worktrees/worktree-test" > "$WT_DIR/2025-06-01-worktree-test/.git"
output=$(try_run --path="$WT_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "git worktree move"; then
    pass
else
    fail "Git worktree should use git worktree move" "git worktree move" "$output" "graduate"
fi

# Test: Regular directory uses plain mv (not git worktree move)
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "git worktree move"; then
    fail "Non-worktree should use mv, not git worktree move" "plain mv" "$output" "graduate"
else
    pass
fi

rm -rf "$GRAD_DIR" "$PROJ_DIR" "$NO_DATE_DIR" "$WT_DIR"
