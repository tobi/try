#!/bin/bash
# Windows Bash (Git Bash / MSYS2) integration for 'try'
# Add this to your ~/.bashrc:
# source /path/to/this/file/try.sh

try() {
    local base_dir="$HOME/src/tries"
    local cmd="$1"
    local arg1="$2"
    local arg2="$3"
    
    # Help
    if [[ "$cmd" == "--help" ]] || [[ "$cmd" == "-h" ]]; then
        echo "try - A simple temporary workspace manager (Bash Version)"
        echo ""
        echo "Usage:"
        echo "  try                            List up to 10 most recent experiment directories"
        echo "  try <project-name>             Create and enter a dated directory for a new project"
        echo "  try clone <url> [name]         Clone a git repo into a dated directory and enter it"
        echo "  try worktree <name>            Create a git worktree from current repo and enter it"
        echo "  try --help (-h)                Show this help message"
        echo ""
        echo "Directories are stored in: $base_dir"
        return
    fi

    # List recent tries
    if [ -z "$cmd" ]; then
        echo "Usage: try <project-name> or try <git-url>"
        echo "Recent tries in $base_dir:"
        mkdir -p "$base_dir"
        ls -dt "$base_dir"/* 2>/dev/null | head -n 10 | while read -r path; do
            basename "$path"
        done
        return
    fi

    # Clone
    if [[ "$cmd" == "clone" ]]; then
        local url="$arg1"
        local custom_name="$arg2"

        if [ -z "$url" ]; then
            echo "Error: clone command requires a URL."
            echo "Usage: try clone <url> [name]"
            return 1
        fi

        local repo_name=$(basename "$url" .git)
        local project_name="${custom_name:-$repo_name}"
        local date_str=$(date +%Y-%m-%d)
        local target_dir="$base_dir/$date_str-$project_name"

        mkdir -p "$base_dir"
        if [ ! -d "$target_dir" ]; then
            echo "Cloning $url into $target_dir..."
            git clone "$url" "$target_dir" || return $?
        else
            echo "Directory $target_dir already exists. Entering it."
        fi
        cd "$target_dir"
        echo "Entered: $target_dir"
        return
    fi

    # Worktree
    if [[ "$cmd" == "worktree" ]]; then
        local wt_name="$arg1"

        if [ -z "$wt_name" ]; then
            echo "Error: worktree command requires a name."
            return 1
        fi

        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "Error: You must be inside a Git repository to use 'worktree'."
            return 1
        fi

        local current_repo_root=$(git rev-parse --show-toplevel)
        local date_str=$(date +%Y-%m-%d)
        local target_dir="$base_dir/$date_str-$wt_name"

        mkdir -p "$base_dir"
        if [ ! -d "$target_dir" ]; then
            echo "Creating worktree '$wt_name' from '$current_repo_root'..."
            git worktree add "$target_dir" "$wt_name" || return $?
        else
            echo "Worktree directory $target_dir already exists. Entering it."
        fi
        cd "$target_dir"
        echo "Entered: $target_dir"
        return
    fi

    # New Project or Direct Git URL
    local project_name="$cmd"
    
    # Handle direct Git URL as first argument
    if [[ "$project_name" == http* ]] || [[ "$project_name" == git@* ]]; then
         local repo_name=$(basename "$project_name" .git)
         local date_str=$(date +%Y-%m-%d)
         local target_dir="$base_dir/$date_str-$repo_name"
         
         mkdir -p "$base_dir"
         if [ ! -d "$target_dir" ]; then
             git clone "$project_name" "$target_dir"
         else
             echo "Directory $target_dir already exists."
         fi
         cd "$target_dir"
         return
    fi

    local date_str=$(date +%Y-%m-%d)
    local target_dir="$base_dir/$date_str-$project_name"
    
    mkdir -p "$target_dir"
    cd "$target_dir"
    echo "Entered: $target_dir"
}
