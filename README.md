# try - fresh directories for every vibe

**[Website](https://pages.tobi.lutke.com/try/)** · **[RubyGems](https://rubygems.org/gems/try-cli)** · **[GitHub](https://github.com/tobi/try)**

*Your experiments deserve a home.* 🏠

> For everyone who constantly creates new projects for little experiments, a one-file Ruby script to quickly manage and navigate to keep them somewhat organized

Ever find yourself with 50 directories named `test`, `test2`, `new-test`, `actually-working-test`, scattered across your filesystem? Or worse, just coding in `/tmp` and losing everything?

**try** is here for your beautifully chaotic mind.

# What it does 

![Fuzzy Search Demo](assets/try-fuzzy-search-demo.gif)

*[View interactive version on asciinema](https://asciinema.org/a/ve8AXBaPhkKz40YbqPTlVjqgs)*

Instantly navigate through all your experiment directories with:
- **Fuzzy search** that just works
- **Smart sorting** - recently used stuff bubbles to the top
- **Auto-dating** - creates directories like `2025-08-17-redis-experiment`
- **Zero config** - Pure Ruby, no external dependencies

## Installation

### RubyGems (Recommended)

```bash
gem install try-cli
```

Then add to your shell:

```bash
# Bash/Zsh - add to .zshrc or .bashrc
eval "$(try init)"

# Fish - add to config.fish
eval (try init | string collect)
```

### Quick Start (Manual)

```bash
curl -sL https://raw.githubusercontent.com/tobi/try/refs/heads/main/try.rb > ~/.local/try.rb

# Make "try" executable so it can be run directly
chmod +x ~/.local/try.rb

# Add to your shell (bash/zsh)
echo 'eval "$(ruby ~/.local/try.rb init ~/src/tries)"' >> ~/.zshrc

# for fish shell users
echo 'eval (~/.local/try.rb init ~/src/tries | string collect)' >> ~/.config/fish/config.fish
```

## The Problem

You're learning Redis. You create `/tmp/redis-test`. Then `~/Desktop/redis-actually`. Then `~/projects/testing-redis-again`. Three weeks later you can't find that brilliant connection pooling solution you wrote at 2am.

## The Solution

All your experiments in one place, with instant fuzzy search:

```bash
$ try pool
→ 2025-08-14-redis-connection-pool    2h, 18.5
  2025-08-03-thread-pool              3d, 12.1
  2025-07-22-db-pooling               2w, 8.3
  + Create new: pool
```

Type, arrow down, enter. You're there.

## Features

### 🎯 Smart Fuzzy Search
Not just substring matching - it's smart:
- `rds` matches `redis-server`
- `connpool` matches `connection-pool`
- Recent stuff scores higher
- Shorter names win on equal matches

### ⏰ Time-Aware
- Shows how long ago you touched each project
- Recently accessed directories float to the top
- Perfect for "what was I working on yesterday?"

### 🎨 Pretty TUI
- Clean, minimal interface
- Highlights matches as you type
- Shows scores so you know why things are ranked
- Dark mode by default (because obviously)

### 📁 Organized Chaos
- Everything lives in `~/src/tries` (configurable via `TRY_PATH`)
- Auto-prefixes with dates: `2025-08-17-your-idea`
- Skip the date prompt if you already typed a name

### Shell Integration

- Bash/Zsh:

  ```bash
  # default is ~/src/tries
  eval "$(~/.local/try.rb init)"
  # or pick a path
  eval "$(~/.local/try.rb init ~/src/tries)"
  ```

- Fish:

  ```fish
  eval (~/.local/try.rb init | string collect)
  # or pick a path
  eval (~/.local/try.rb init ~/src/tries | string collect)
  ```

Notes:
- The runtime commands printed by `try` are shell-neutral (absolute paths, quoted). Only the small wrapper function differs per shell.

## Usage

```bash
try                                          # Browse all experiments
try redis                                    # Jump to redis experiment or create new
try new api                                  # Start with "2025-08-17-new-api"
try . <name>                                 # Create a dated worktree dir for current repo
try ./path/to/repo [name]                    # Use another repo as the worktree source
try worktree dir [name]                      # Explicit worktree form for current repo
try clone https://github.com/user/repo.git   # Clone repo into date-prefixed directory
try https://github.com/user/repo.git         # Shorthand for clone (same as above)
try --help                                   # See all options
try --version                                # Show version
```

Notes on worktrees (`try .` / `try worktree dir`):
- `try .` requires a name (`try . <name>`).
- `try ./path/to/repo [name]` and `try worktree dir [name]` use cwd basename when name is omitted.
- Inside a Git repo: adds a detached HEAD git worktree to the created directory.
- Outside a repo: simply creates the directory and changes into it.

### Git Repository Cloning

**try** can automatically clone git repositories into properly named experiment directories:

```bash
# Clone with auto-generated directory name
try clone https://github.com/tobi/try.git
# Creates: 2025-08-27-tobi-try

# Clone with custom name
try clone https://github.com/tobi/try.git my-fork
# Creates: my-fork

# Shorthand syntax (no need to type 'clone')
try https://github.com/tobi/try.git
# Creates: 2025-08-27-tobi-try
```

Supported git URI formats:
- `https://github.com/user/repo.git` (HTTPS GitHub)
- `git@github.com:user/repo.git` (SSH GitHub)
- `https://gitlab.com/user/repo.git` (GitLab)
- `git@host.com:user/repo.git` (SSH other hosts)

The `.git` suffix is automatically removed from URLs when generating directory names.

### Keyboard Shortcuts

- `↑/↓` or `Ctrl-P/N` - Navigate
- `Enter` - Select or create
- `Backspace` - Delete character
- `Ctrl-D` - Mark directory for deletion (confirm on exit)
- `Ctrl-R` - Rename selected entry
- `Ctrl-G` - Graduate (promote try to project)
- `Ctrl-T` - Create new try immediately
- `Ctrl-A/E` - Beginning/end of line
- `Ctrl-B/F` - Backward/forward character
- `Ctrl-K` - Delete to end of line
- `Ctrl-W` - Delete word backward
- `ESC` - Cancel
- Just type to filter

## Configuration

### Environment Variables

- `TRY_PATH` - Where experiments are stored (default: `~/src/tries`)
- `TRY_PROJECTS` - Graduate destination for promoted experiments (default: parent of `TRY_PATH`)
- `NO_COLOR` - Disable colored output when set

```bash
export TRY_PATH=~/code/sketches
export TRY_PROJECTS=~/projects
```

### Command Line Flags

- `--path PATH` - Override the root path for a single invocation
- `--no-colors` - Disable colored output
- `--help` / `-h` - Show help
- `--version` / `-v` - Show version

Examples:
```bash
try --path ~/other-tries redis    # Use different root for this command
try --no-colors                   # Disable colors
```

## Nix

### Quick start

```bash
nix run github:tobi/try
nix run github:tobi/try -- --help
nix run github:tobi/try init ~/my-tries
```

### Home Manager

```nix
{
  inputs.try.url = "github:tobi/try";
  
  imports = [ inputs.try.homeManagerModules.default ];
  
  programs.try = {
    enable = true;
    path = "~/experiments";  # optional, defaults to ~/src/tries
  };
}
```

## Homebrew

### Quick start

```bash
brew tap tobi/try https://github.com/tobi/try
brew install try
```

After installation, add to your shell:

- Bash/Zsh:

  ```bash
  # default is ~/src/tries
  eval "$(try init)"
  # or pick a path
  eval "$(try init ~/src/tries)"
  ```

- Fish:

  ```fish
  eval "(try init | string collect)"
  # or pick a path
  eval "(try init ~/src/tries | string collect)"
  ```

## Why Ruby?

- Pure Ruby, no external dependencies
- Works on any system with Ruby (macOS has it built-in)
- Fast enough for thousands of directories
- Easy to hack on

## The Philosophy

Your brain doesn't work in neat folders. You have ideas, you try things, you context-switch like a caffeinated squirrel. This tool embraces that.

Every experiment gets a home. Every home is instantly findable. Your 2am coding sessions are no longer lost to the void.

## FAQ

**Q: Why not just use `cd` and `ls`?**
A: Because you have 200 directories and can't remember if you called it `test-redis`, `redis-test`, or `new-redis-thing`.

**Q: Why not use `fzf`?**
A: fzf is great for files. This is specifically for project directories, with time-awareness and auto-creation built in.

**Q: Can I use this for real projects?**
A: You can, but it's designed for experiments. Real projects deserve real names in real locations.

**Q: What if I have thousands of experiments?**
A: First, welcome to the club. Second, it handles it fine - the scoring algorithm ensures relevant stuff stays on top.

## Contributing

If you want to change something, just edit it. The code is modular and easy to navigate. Send a PR if you think others would like it too.

## License

MIT - Do whatever you want with it.

---

*Built for developers with ADHD by developers with ADHD.*

*Your experiments deserve a home.* 🏠
