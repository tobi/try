# Migrate tests
# Spec: command_line.md#migrate

section "migrate"

MIG_TRIES=$(mktemp -d)
MIG_SRC=$(mktemp -d)
today=$(date +%Y-%m-%d)

# Test: ESC cancels without producing a move
mkdir -p "$MIG_SRC/cancel-me"
output=$(cd "$MIG_SRC/cancel-me" && try_run --path="$MIG_TRIES" --and-keys='ESC' exec migrate 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv "; then
    pass
else
    fail "Esc should cancel migrate" "no mv" "$output" "command_line.md#migrate"
fi

# Test: ENTER accepts default date-prefixed target
mkdir -p "$MIG_SRC/plain-exp"
output=$(cd "$MIG_SRC/plain-exp" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "mv '.*' '$MIG_TRIES/$today-plain-exp'"; then
    pass
else
    fail "Migrate should mv to date-prefixed target" "$MIG_TRIES/$today-plain-exp" "$output" "command_line.md#migrate"
fi

# Test: Script includes cd to destination
if echo "$output" | grep -q "cd '$MIG_TRIES/$today-plain-exp'"; then
    pass
else
    fail "Migrate script should cd to destination" "cd to target" "$output" "command_line.md#migrate"
fi

# Test: Named directory argument
mkdir -p "$MIG_SRC/other-exp"
output=$(cd "$MIG_SRC" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate other-exp 2>/dev/null)
if echo "$output" | grep -q "mv '.*/other-exp' '$MIG_TRIES/$today-other-exp'"; then
    pass
else
    fail "Migrate <dir> should move that directory" "$MIG_TRIES/$today-other-exp" "$output" "command_line.md#migrate"
fi

# Test: Already date-prefixed name is kept (no double prefix)
mkdir -p "$MIG_SRC/2025-06-01-prefixed"
output=$(cd "$MIG_SRC" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2025-06-01-prefixed 2>/dev/null)
if echo "$output" | grep -q "mv '.*/2025-06-01-prefixed' '$MIG_TRIES/2025-06-01-prefixed'"; then
    pass
else
    fail "Already-prefixed name should be kept" "no double prefix" "$output" "command_line.md#migrate"
fi

# Test: Collision bumps target to -2
mkdir -p "$MIG_TRIES/$today-dup-exp"
mkdir -p "$MIG_SRC/dup-exp"
output=$(cd "$MIG_SRC/dup-exp" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "$MIG_TRIES/$today-dup-exp-2"; then
    pass
else
    fail "Collision should bump target to -2" "$MIG_TRIES/$today-dup-exp-2" "$output" "command_line.md#migrate"
fi

# Test: Editable target name
mkdir -p "$MIG_SRC/edit-exp"
output=$(cd "$MIG_SRC/edit-exp" && try_run --path="$MIG_TRIES" --and-keys='CTRL-A,CTRL-K,TYPE=custom-target,ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "mv '.*' '$MIG_TRIES/custom-target'"; then
    pass
else
    fail "Edited target name should be used" "$MIG_TRIES/custom-target" "$output" "command_line.md#migrate"
fi

# Test: Worktree (.git file) uses git worktree move
mkdir -p "$MIG_SRC/worktree-exp"
echo "gitdir: /tmp/fake-repo/.git/worktrees/worktree-exp" > "$MIG_SRC/worktree-exp/.git"
output=$(cd "$MIG_SRC/worktree-exp" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "git worktree move"; then
    pass
else
    fail "Worktree should use git worktree move" "git worktree move" "$output" "command_line.md#migrate"
fi

# Test: Warning shown when inside a git repository (not the root)
GIT_REPO=$(mktemp -d)
mkdir -p "$GIT_REPO/.git" "$GIT_REPO/subdir"
output=$(cd "$GIT_REPO/subdir" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "inside a git repository"; then
    pass
else
    fail "Inside-repo migrate should warn about git" "warning text" "$output" "command_line.md#migrate"
fi

# Test: No warning for a repository root (own .git dir)
output=$(cd "$GIT_REPO" && try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate 2>/dev/null)
if echo "$output" | grep -q "inside a git repository"; then
    fail "Repo root migrate should not warn" "no warning" "$output" "command_line.md#migrate"
else
    pass
fi

# Test: Refuses to migrate the tries directory itself
output=$(try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate "$MIG_TRIES" 2>/dev/null)
if echo "$output" | grep -q "Error"; then
    pass
else
    fail "Migrating tries root should error" "Error" "$output" "command_line.md#migrate"
fi

# Test: Refuses to migrate a directory already inside tries
mkdir -p "$MIG_TRIES/2025-11-01-alpha"
output=$(try_run --path="$MIG_TRIES" --and-keys='ENTER' exec migrate "$MIG_TRIES/2025-11-01-alpha" 2>/dev/null)
if echo "$output" | grep -q "Error"; then
    pass
else
    fail "Migrating a dir already in tries should error" "Error" "$output" "command_line.md#migrate"
fi

# Test: Empty target name is rejected (no move)
mkdir -p "$MIG_SRC/empty-exp"
output=$(cd "$MIG_SRC/empty-exp" && try_run --path="$MIG_TRIES" --and-keys='CTRL-A,CTRL-K,ENTER,ESC' exec migrate 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv "; then
    pass
else
    fail "Empty target name should not produce mv" "no mv" "$output" "command_line.md#migrate"
fi

# Test: E2E — actually move the directory and keep its contents
E2E_SRC=$(mktemp -d)
mkdir -p "$E2E_SRC/real-exp"
echo "hello" > "$E2E_SRC/real-exp/file.txt"
script=$(cd "$E2E_SRC/real-exp" && eval $TRY_CMD exec --path="$MIG_TRIES" --and-keys='ENTER' migrate 2>/dev/null)
eval "$(echo "$script" | grep -v '^#')" 2>/dev/null
if [ -f "$MIG_TRIES/$today-real-exp/file.txt" ]; then
    pass
else
    fail "E2E: file should exist at migrated destination" "$MIG_TRIES/$today-real-exp/file.txt" "$(ls -la $MIG_TRIES/ 2>&1)" "command_line.md#migrate"
fi

# Test: E2E — source directory no longer exists
if [ ! -d "$E2E_SRC/real-exp" ]; then
    pass
else
    fail "E2E: source should be gone after migrate" "no $E2E_SRC/real-exp" "$(ls -la $E2E_SRC/ 2>&1)" "command_line.md#migrate"
fi

# Cleanup
rm -rf "$MIG_TRIES" "$MIG_SRC" "$GIT_REPO" "$E2E_SRC"
