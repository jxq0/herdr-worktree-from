# herdr-worktree-from

A Herdr plugin that opens a Git worktree for a branch picked from a
fuzzy-filtered list of local and remote branches.

Press `prefix+ctrl+g` and type a few letters to filter:

```text
Branch > fea
feature/foo          local   2 days ago
origin/feature-bar   remote  3 weeks ago
```

Two keys open a worktree:

- **Enter** opens a worktree on the picked branch. A local branch is used as
  is; a branch that is already checked out elsewhere just focuses that
  workspace. A remote branch becomes a local branch with the same short name
  based on the remote tip, and reuses the local branch when one already has
  that name.
- **alt-enter** asks for a new branch name, then opens a worktree on that new
  branch, based on the picked ref. The name is required: an empty line cancels
  and nothing is created.

When the query matches nothing, neither key does anything. The picker stays
open until the query matches something or Esc is pressed.

fzf has no ctrl-enter key, so the second action is on alt-enter.

The bottom bar shows the repository, the current branch, how many local and
remote branches there are, and the key hints. It uses fzf's footer, so fzf
0.63 or newer is needed; older versions show the same text as a header instead.

## Requirements

- Herdr 0.9.0 or newer
- `git`, `fzf`, and optionally `jq` (used to read the invocation context and to
  print Herdr's error message). fzf 0.63 or newer draws the bottom status bar.

## Install

Install from GitHub:

```bash
herdr plugin install jxq0/herdr-worktree-from
```

Add `--ref <tag-or-commit>` to pin a revision instead of tracking the default
branch.

To hack on the plugin, clone it and link the clone instead, running this from
the clone's directory:

```bash
herdr plugin link .
```

Then bind a key in `config.toml`:

```toml
[[keys.command]]
key = "prefix+ctrl+g"
type = "plugin_action"
command = "worktree-from.open"
description = "new worktree from a branch"
```

Reload:

```bash
herdr server reload-config
```

Herdr's own new-worktree flow stays on `prefix+shift+g`; this plugin does not
replace it.

## How it works

`bin/open.sh` reads `HERDR_PLUGIN_CONTEXT_JSON`, passes the focused pane's
repository root as the popup's `--cwd`, and opens the picker pane.
`bin/picker.sh` runs `fzf` over `git for-each-ref refs/heads refs/remotes`,
skipping remote `HEAD` entries. Enter prints the selection, alt-enter also
touches a temp file so the script knows which of the two keys was used. Both
keys are ignored while the query has no match. The script then calls one of:

```bash
herdr worktree create --cwd <repo> --branch <branch> --label <branch> --focus
herdr worktree create --cwd <repo> --branch <short> --base <remote ref> --focus
herdr worktree create --cwd <repo> --base <ref> --branch <name> --label <name> --focus
```

The first opens a worktree on an existing local branch, or on a local branch
that already shares its short name with the picked remote branch. The second
creates the local branch from the remote tip. The third is alt-enter: a new
branch based on the picked ref. Herdr resolves the repository, checks the
branch out or creates it from the base, and opens or focuses the workspace.

## Debugging

Run these from a clone of the repository, inside the Git repository you want
to inspect:

```bash
./bin/picker.sh --list       # candidate refs, no UI
./bin/picker.sh --dry-run    # pick a branch, then print the herdr command only
```
