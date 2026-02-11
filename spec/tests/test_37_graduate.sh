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

# Test: Symlink source path points to the original try basename
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
symlink_line=$(echo "$output" | grep "ln -s ")
if echo "$symlink_line" | grep -q "2025-06-01-my-experiment"; then
    pass
else
    fail "Symlink should be created at original try path" "2025-06-01-my-experiment in ln -s" "$symlink_line" "graduate"
fi

# Test: Symlink target matches the mv destination
mv_dest=$(echo "$output" | grep "^mv \|^  mv " | grep -oP "'\K[^']+(?=')" | tail -1)
ln_target=$(echo "$output" | grep "ln -s " | grep -oP "'\K[^']+(?=')" | head -1)
if [ "$mv_dest" = "$ln_target" ]; then
    pass
else
    fail "Symlink target should match mv destination" "$mv_dest" "$ln_target" "graduate"
fi

# Test: Ctrl-G then Ctrl-C also cancels
output=$(try_run --path="$GRAD_DIR" --and-keys='CTRL-G,CTRL-D' exec 2>/dev/null)
if echo "$output" | grep -q "mv "; then
    fail "Ctrl-G then Ctrl-C/D should cancel" "no mv" "$output" "graduate"
else
    pass
fi

# Test: Editing destination — clear and type new path
# Ctrl-A goes to start, Ctrl-K kills to end, then type new destination
EDIT_DIR=$(mktemp -d)
mkdir -p "$EDIT_DIR/2025-06-01-editme"
DEST_DIR=$(mktemp -d)
output=$(try_run --path="$EDIT_DIR" --and-keys="CTRL-G,CTRL-A,CTRL-K,TYPE=${DEST_DIR}/custom-name,ENTER" exec 2>/dev/null)
if echo "$output" | grep "mv " | grep -q "$DEST_DIR/custom-name"; then
    pass
else
    fail "Should be able to edit destination path" "$DEST_DIR/custom-name" "$output" "graduate"
fi

# Test: Edited destination appears in symlink target too
if echo "$output" | grep "ln -s " | grep -q "$DEST_DIR/custom-name"; then
    pass
else
    fail "Symlink target should match edited destination" "$DEST_DIR/custom-name" "$output" "graduate"
fi

# Test: End-to-end — actually execute the graduate script
E2E_DIR=$(mktemp -d)
E2E_DEST=$(mktemp -d)
mkdir -p "$E2E_DIR/2025-06-01-real-test"
echo "hello" > "$E2E_DIR/2025-06-01-real-test/file.txt"
# Must capture stdout only (not stderr which has TUI render output)
script=$(eval $TRY_CMD exec --path="$E2E_DIR" --and-keys="CTRL-G,CTRL-A,CTRL-K,TYPE=${E2E_DEST}/graduated-project,ENTER" 2>/dev/null)
# Execute the script (skip the warning comment line)
eval "$(echo "$script" | grep -v '^#')" 2>/dev/null
if [ -f "$E2E_DEST/graduated-project/file.txt" ]; then
    pass
else
    fail "E2E: file should exist at graduated destination" "$E2E_DEST/graduated-project/file.txt" "$(ls -la $E2E_DEST/ 2>&1)" "graduate"
fi

# Test: E2E — symlink exists and points to destination
if [ -L "$E2E_DIR/2025-06-01-real-test" ]; then
    pass
else
    fail "E2E: symlink should exist at original location" "symlink at $E2E_DIR/2025-06-01-real-test" "$(ls -la $E2E_DIR/ 2>&1)" "graduate"
fi

# Test: E2E — symlink resolves to correct destination
link_target=$(readlink "$E2E_DIR/2025-06-01-real-test")
if [ "$link_target" = "$E2E_DEST/graduated-project" ]; then
    pass
else
    fail "E2E: symlink should point to graduated destination" "$E2E_DEST/graduated-project" "$link_target" "graduate"
fi

# Test: E2E — original content is accessible through symlink
if [ "$(cat "$E2E_DIR/2025-06-01-real-test/file.txt")" = "hello" ]; then
    pass
else
    fail "E2E: content should be accessible through symlink" "hello" "$(cat $E2E_DIR/2025-06-01-real-test/file.txt 2>&1)" "graduate"
fi

# Test: Graduate with .git directory (regular repo, not worktree) uses mv
REG_DIR=$(mktemp -d)
mkdir -p "$REG_DIR/2025-06-01-regular-repo/.git/objects"
output=$(try_run --path="$REG_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "git worktree move"; then
    fail "Regular .git directory should use mv, not git worktree move" "plain mv" "$output" "graduate"
else
    pass
fi
if echo "$output" | grep -q "^mv \|  mv "; then
    pass
else
    fail "Regular .git directory should use plain mv" "mv command" "$output" "graduate"
fi

# Test: Multiple date-prefix formats strip correctly
MULTI_DIR=$(mktemp -d)
mkdir -p "$MULTI_DIR/2025-12-31-year-end"
output=$(try_run --path="$MULTI_DIR" --and-keys='CTRL-G,ENTER' exec 2>/dev/null)
if echo "$output" | grep "mv " | grep -q "/year-end'"; then
    pass
else
    fail "Should strip YYYY-MM-DD- prefix from various dates" "year-end" "$output" "graduate"
fi

rm -rf "$GRAD_DIR" "$PROJ_DIR" "$NO_DATE_DIR" "$WT_DIR" "$EDIT_DIR" "$E2E_DIR" "$E2E_DEST" "$REG_DIR" "$MULTI_DIR"
