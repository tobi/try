# Graduation Specification

`Ctrl-G` opens a confirmation dialog for promoting the selected try to a
permanent project directory.

## Destination defaults

The project name is the try name with a leading `YYYY-MM-DD-` removed. The
default destination is:

1. the first path in `TRY_PROJECTS`, when it is set;
2. otherwise the parent directory of `TRY_PATH`.

`TRY_PROJECTS` may contain one or more absolute or `~`-relative parent paths,
separated by the platform path separator (`:` on Unix-like systems). Existing
single-path configurations remain valid. Parent paths are expanded and empty
entries are ignored.

## Graduation dialog

The dialog shows the destination path in an editable input field. Paths
inside the user's home directory are displayed with a `~` prefix when
possible, while the actual expanded path is used for graduation.

- Left/right arrows and the line-editing keys move and edit the destination.
- With multiple configured parents, Up/Down arrows cycle through them.
- Cycling parents preserves the current project basename, including a basename
  manually typed into the destination field.
- Parent selection wraps at the beginning and end of the configured list.
- Enter confirms; Esc or Ctrl-C cancels.

When multiple parents are configured, the dialog lists every parent in a
centered, aligned block whose path columns line up with the destination field.
The shared directory prefix is dimmed and the
non-shared suffix is bold for each entry; the active entry is marked with `→`.
Below the list, contextual help shows bold `↑↓` and `←→` icons with the labels
`select parent, edit`. Enter/Esc confirmation help is shown separately in the
footer. The destination parent must already exist and the complete destination
must not already exist.

## Result

On confirmation, the shell script:

1. moves the try to the selected destination;
2. leaves a symlink at the original try path;
3. prints a graduation message; and
4. changes the shell to the new project directory.

Git worktrees use `git worktree move`; regular directories use `mv`.
