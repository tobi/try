# Execute emitted scripts against real worktrees, outside their repository.
# Spec: tui_spec.md#rename-and-delete-git-worktrees, delete_spec.md

section "worktree lifecycle"

# Earlier specs may delete the directory they leave as the runner's cwd.
cd "$TEST_ROOT" || return 1

wt_emit() {
    set -- "--path=$wt_tries" "--and-keys=$1" exec
    eval $TRY_CMD '"$@"' 2>/dev/null
}

wt_check() {
    if "$@" >/dev/null 2>&1; then
        pass
    else
        fail "$wt_description" "successful worktree operation" "$wt_script" "tui_spec.md#rename-and-delete-git-worktrees"
    fi
}

wt_root="$TEST_ROOT/worktree-lifecycle"
mkdir -p "$wt_root"
wt_root=$(cd "$wt_root" && pwd -P)
wt_repo="$wt_root/owner's repo"
wt_tries="$wt_root/owner's tries"
wt_old="$wt_tries/2025-01-01-owner's-experiment"
wt_new="$wt_tries/renamed"
mkdir -p "$wt_repo" "$wt_tries"
git -C "$wt_repo" init -q --initial-branch=main
echo committed > "$wt_repo/tracked.txt"
git -C "$wt_repo" add tracked.txt
git -C "$wt_repo" -c user.name=Test -c user.email=test@example.com \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm initial
git -C "$wt_repo" worktree add -q -b experiment "$wt_old"

# Preserve staged, unstaged, and untracked files when moving a worktree.
echo staged > "$wt_old/tracked.txt"
git -C "$wt_old" add tracked.txt
echo unstaged >> "$wt_old/tracked.txt"
echo untracked > "$wt_old/untracked.txt"
wt_status=$(git -C "$wt_old" status --porcelain)
wt_script=$(wt_emit 'CTRL-R,CTRL-A,CTRL-K,TYPE=renamed,ENTER')
wt_description="rename emitted script runs from outside the repository"
wt_check bash -c "$wt_script"
wt_description="renamed worktree remains usable"
wt_check git -C "$wt_new" rev-parse --verify HEAD
wt_description="rename preserves staged and unstaged changes"
wt_check test "$(git -C "$wt_new" status --porcelain)" = "$wt_status"
wt_description="rename updates Git registration"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -Fxc "worktree $wt_new")" = 1
wt_description="rename removes the old path"
wt_check test ! -e "$wt_old"
wt_description="rename keeps the branch name"
wt_check test "$(git -C "$wt_new" branch --show-current)" = experiment

# A graduated worktree's symlink must not act on the target.
wt_link="$wt_tries/shortcut"
ln -s "$wt_new" "$wt_link"
wt_script=$(wt_emit 'TYPE=shortcut,CTRL-R,CTRL-A,CTRL-K,TYPE=renamed-link,ENTER')
wt_description="rename a symlink to a worktree"
wt_check bash -c "$wt_script"
wt_description="renamed symlink still points at the worktree"
wt_check test "$(readlink "$wt_tries/renamed-link")" = "$wt_new"
wt_script=$(wt_emit 'TYPE=renamed-link,CTRL-D,ENTER,Y,E,S,ENTER')
wt_description="delete the symlink"
wt_check bash -c "$wt_script"
wt_description="deleting a symlink keeps its worktree target"
wt_check test -f "$wt_new/untracked.txt"
wt_description="delete removes the symlink"
wt_check test ! -L "$wt_tries/renamed-link"

# Locked worktrees must not fall back to mv or rm -rf.
git -C "$wt_repo" worktree lock "$wt_new"
wt_script=$(wt_emit 'CTRL-R,CTRL-A,CTRL-K,TYPE=blocked,ENTER')
bash -c "$wt_script" >/dev/null 2>&1
wt_description="locked worktree cannot be renamed"
wt_check test -f "$wt_new/untracked.txt"
wt_description="failed rename creates no destination"
wt_check test ! -e "$wt_tries/blocked"
wt_script=$(wt_emit 'CTRL-D,ENTER,Y,E,S,ENTER')
bash -c "$wt_script" >/dev/null 2>&1
wt_description="locked worktree cannot be deleted"
wt_check test -f "$wt_new/untracked.txt"
git -C "$wt_repo" worktree unlock "$wt_new"

# The original YES confirmation is still required for worktrees.
wt_script=$(wt_emit 'CTRL-D,ENTER,N,O,ENTER')
wt_description="declining deletion emits no removal command"
wt_check test "$(printf '%s' "$wt_script" | grep -c 'worktree remove\|rm -rf')" = 0
wt_script=$(wt_emit 'CTRL-D,ENTER,Y,E,S,ENTER')
wt_description="confirmed deletion removes a dirty worktree"
wt_check bash -c "$wt_script"
wt_description="delete removes the directory"
wt_check test ! -e "$wt_new"
wt_description="delete removes Git registration"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -c '^worktree ')" = 1
wt_description="delete keeps the experiment branch"
wt_check git -C "$wt_repo" show-ref --verify --quiet refs/heads/experiment

# A .git file also occurs in standalone repositories with a separate git dir.
wt_separate="$wt_tries/separate"
git init -q --separate-git-dir="$wt_root/separate.git" "$wt_separate"
echo keep > "$wt_separate/file.txt"
wt_script=$(wt_emit 'CTRL-R,CTRL-A,CTRL-K,TYPE=standalone,ENTER')
wt_description="standalone repo with a .git file can be renamed"
wt_check bash -c "$wt_script"
wt_description="standalone repository content survives rename"
wt_check test -f "$wt_tries/standalone/file.txt"
wt_script=$(wt_emit 'CTRL-D,ENTER,Y,E,S,ENTER')
wt_description="standalone repo with a .git file can be deleted"
wt_check bash -c "$wt_script"
wt_description="standalone repo directory was deleted"
wt_check test ! -e "$wt_tries/standalone"

# One batch may contain plain directories, standalone repos, and worktrees.
git -C "$wt_repo" worktree add -q -b batch "$wt_tries/worktree"
mkdir "$wt_tries/plain"
git init -q "$wt_tries/repo"
wt_script=$(wt_emit 'CTRL-D,DOWN,CTRL-D,DOWN,CTRL-D,ENTER,Y,E,S,ENTER')
wt_description="mixed batch deletion succeeds"
wt_check bash -c "$wt_script"
wt_description="mixed batch removes all entries"
wt_check test "$(ls -A "$wt_tries" | wc -l | tr -d ' ')" = 0
wt_description="mixed batch unregisters the worktree"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -c '^worktree ')" = 1

# Stock try creates detached worktrees rather than named branches.
wt_detached="$wt_tries/detached"
git -C "$wt_repo" worktree add -q --detach "$wt_detached"
wt_head=$(git -C "$wt_detached" rev-parse HEAD)
wt_script=$(wt_emit 'CTRL-R,CTRL-A,CTRL-K,TYPE=renamed-detached,ENTER')
wt_description="rename detached worktree"
wt_check bash -c "$wt_script"
wt_detached="$wt_tries/renamed-detached"
wt_description="renamed detached worktree keeps its HEAD"
wt_check test "$(git -C "$wt_detached" rev-parse HEAD)" = "$wt_head"
wt_description="rename leaves the worktree detached"
wt_check test -z "$(git -C "$wt_detached" branch --show-current)"
wt_description="rename updates detached worktree registration"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -Fxc "worktree $wt_detached")" = 1
wt_script=$(wt_emit 'CTRL-D,ENTER,Y,E,S,ENTER')
wt_description="delete detached worktree"
wt_check bash -c "$wt_script"
wt_description="delete removes detached worktree directory"
wt_check test ! -e "$wt_detached"
wt_description="delete unregisters detached worktree"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -c '^worktree ')" = 1

# Graduate uses the same detection and works outside the parent repository.
wt_grad="$wt_tries/2025-01-01-graduate"
wt_dest="$wt_root/owner's graduated project"
git -C "$wt_repo" worktree add -q --detach "$wt_grad"
echo untracked > "$wt_grad/untracked.txt"
wt_script=$(wt_emit "CTRL-G,CTRL-A,CTRL-K,TYPE=$wt_dest,ENTER")
wt_description="graduate worktree from outside its repository"
wt_check bash -c "$wt_script"
wt_description="graduation preserves worktree files"
wt_check test -f "$wt_dest/untracked.txt"
wt_description="graduated worktree remains usable"
wt_check git -C "$wt_dest" rev-parse --verify HEAD
wt_description="graduation leaves the worktree detached"
wt_check test -z "$(git -C "$wt_dest" branch --show-current)"
wt_description="graduation updates Git registration"
wt_check test "$(git -C "$wt_repo" worktree list --porcelain | grep -Fxc "worktree $wt_dest")" = 1
wt_description="graduation leaves a symlink"
wt_check test "$(readlink "$wt_grad")" = "$wt_dest"

# Separate Git directories must not be mistaken for linked worktrees.
wt_tries="$wt_root/standalone tries"
mkdir "$wt_tries"
git init -q --separate-git-dir="$wt_root/graduate.git" "$wt_tries/separate"
echo keep > "$wt_tries/separate/file.txt"
wt_dest="$wt_root/standalone project"
wt_script=$(wt_emit "CTRL-G,CTRL-A,CTRL-K,TYPE=$wt_dest,ENTER")
wt_description="graduate standalone repository with a .git file"
wt_check bash -c "$wt_script"
wt_description="standalone graduation preserves files"
wt_check test -f "$wt_dest/file.txt"
wt_description="standalone graduation leaves a symlink"
wt_check test "$(readlink "$wt_tries/separate")" = "$wt_dest"
