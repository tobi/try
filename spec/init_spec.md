# Init Command Specification

The `init` command outputs a shell function definition that must be evaluated (sourced) by the user's shell to enable the `try` command.

## Purpose

The shell function wrapper is necessary because:
1. A subprocess cannot change the parent shell's working directory
2. The wrapper captures `try exec` output and `eval`s it in the current shell
3. This allows commands like `cd` to actually change the current directory

## Shell Detection

The init command should detect the user's shell via the `$SHELL` environment variable and output the appropriate function syntax.

Supported shells:
- **Bash/Zsh**: POSIX-compatible function syntax
- **Fish**: Fish-specific function syntax

## Function Output Format

### Bash/Zsh Format

```bash
try() {
  local out
  out=$('/path/to/try' exec --path '/default/tries/path' "$@" 2>/dev/tty)
  if [ $? -eq 0 ]; then
    eval "$out"
  else
    echo "$out"
  fi
}
```

Key elements:
- Function name: `try`
- Captures `try exec` output to local variable
- Redirects stderr to `/dev/tty` (TUI renders to stderr)
- Exit code 0: Evaluates the output (executes cd, git clone, etc.)
- Exit code non-0: Prints the output (shows error/cancellation message)

### Fish Format

```fish
function try
  set -l out (/path/to/try exec --path '/default/tries/path' $argv 2>/dev/tty)
  if test $status -eq 0
    eval $out
  else
    echo $out
  end
end
```

## Path Embedding

The init output must embed:
1. The full path to the `try` binary (resolved at init time)
2. The default tries path (typically `~/src/tries`)

This ensures the wrapper always calls the correct binary regardless of `$PATH` changes.

## Installation Instructions

The user should add one of the following to their shell configuration:

### Bash (~/.bashrc)
```bash
eval "$(try init)"
```

### Zsh (~/.zshrc)
```zsh
eval "$(try init)"
```

### Fish (~/.config/fish/config.fish)
```fish
try init | source
```

## Exit Code Semantics

The wrapper interprets `try exec` exit codes:

| Exit Code | Meaning | Wrapper Action |
|-----------|---------|----------------|
| 0 | Success | `eval` the output (execute shell commands) |
| 1 | Cancelled/Error | Print the output (show message to user) |

## Testing

Test that init produces valid shell syntax:
```bash
# Test Bash syntax
bash -n <(try init)

# Test Fish syntax (if fish is available)
fish -n <(SHELL=/usr/bin/fish try init)
```

Test that the wrapper works correctly:
```bash
eval "$(try init)"
try cd  # Should launch selector and cd on selection
```
