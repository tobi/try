#!/bin/bash
# Windows Bash (Git Bash / MSYS2) integration for 'try'
# Add this to your ~/.bashrc:
# source /path/to/this/file/try.sh

try() {
    local base_dir="$HOME/src/tries"
    local cmd="$1"
    local arg1="$2"
    local arg2="$3"
    
    # Helper to get unique directory name with versioning
    get_unique_dir_name() {
        local base_path="$1"
        local date_prefix="$2"
        local name="$3"

        local initial="$date_prefix-$name"
        local full_path="$base_path/$initial"
        if [ ! -d "$full_path" ]; then
            echo "$name"
            return
        fi

        # Check if name ends with digits
        if [[ "$name" =~ ^(.*[^0-9])([0-9]+)$ ]]; then
            local stem="${BASH_REMATCH[1]}"
            local num=$((${BASH_REMATCH[2]} + 1))
            while true; do
                local candidate="$stem$num"
                local candidate_full="$base_path/$date_prefix-$candidate"
                if [ ! -d "$candidate_full" ]; then
                    echo "$candidate"
                    return
                fi
                ((num++))
            done
        else
            # No numeric suffix; use -2 style
            local i=2
            while true; do
                local candidate="$name-$i"
                local candidate_full="$base_path/$date_prefix-$candidate"
                if [ ! -d "$candidate_full" ]; then
                    echo "$candidate"
                    return
                fi
                ((i++))
            done
        fi
    }

    # Help
    if [[ "$cmd" == "--help" ]] || [[ "$cmd" == "-h" ]]; then
        echo "try - A simple temporary workspace manager (Bash Version)"
        echo ""
        echo "Usage:"
        echo "  try                            List up to 10 most recent experiment directories"
        echo "  try <project-name>             Create and enter a dated directory for a new project"
        echo "  try . <name>                   Create a dated worktree dir for current repo"
        echo "  try ./path/to/repo [name]      Use another repo as the worktree source"
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

    # Dot notation: try . [name] or try ./path/to/repo [name]
    if [[ "$cmd" == "." ]] || [[ "$cmd" == ./* ]]; then
        local repo_dir
        local custom_name

        if [[ "$cmd" == "." ]]; then
            repo_dir="$(pwd)"
            custom_name="$arg1"
            # "try ." requires a name argument (too easy to invoke accidentally)
            if [ -z "$custom_name" ]; then
                echo "Error: 'try .' requires a name argument."
                echo "Usage: try . <name>"
                return 1
            fi
        else
            repo_dir="$(cd "$cmd" 2>/dev/null && pwd)"
            if [ -z "$repo_dir" ]; then
                echo "Error: Path not found: $cmd"
                return 1
            fi
            custom_name="$arg1"
        fi

        # Determine base name
        local base_name
        if [ -n "$custom_name" ]; then
            base_name="${custom_name// /-}"
        else
            base_name="$(basename "$repo_dir")"
        fi

        local date_str=$(date +%Y-%m-%d)
        base_name=$(get_unique_dir_name "$base_dir" "$date_str" "$base_name")
        local target_dir="$base_dir/$date_str-$base_name"

        mkdir -p "$base_dir"

        # Check if it's a git repo and use worktree
        if [ -d "$repo_dir/.git" ]; then
            if [ ! -d "$target_dir" ]; then
                echo "Creating worktree from '$repo_dir'..."
                git -C "$repo_dir" worktree add --detach "$target_dir" 2>/dev/null || mkdir -p "$target_dir"
            fi
        else
            # Not a git repo, just create directory
            mkdir -p "$target_dir"
        fi

        cd "$target_dir"
        echo "Entered: $target_dir"
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
