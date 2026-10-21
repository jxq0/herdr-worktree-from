# herdr-worktree-from

A Herdr plugin that opens a Git worktree for a branch picked from a
fuzzy-filtered list of local and remote branches, or starts a brand-new branch
when the typed name matches nothing.

Press `prefix+ctrl+g` and type a few letters to filter:

```text
Branch > fea
feature/foo          local   2 days ago
origin/feature-bar   remote  3 weeks ago
```

What Enter does:

- Local branch that no worktree has checked out: the worktree opens on it.
- Local branch already checked out, or a remote branch whose short name is
  taken locally: it asks for a new branch name based on the picked ref. Leave
  the name empty to let Herdr generate `worktree/<adjective>-<noun>-<hex>`.
- Remote branch with no local counterpart: a local branch with the same short
  name is created from the remote tip.
- Query matches nothing: the query becomes the new branch name, based on the
  current HEAD.

The bottom bar shows the repository, the current branch, how many local and
remote branches there are, and the key hints. It uses fzf's footer, so fzf
0.63 or newer is needed; older versions show the same text as a header instead.

## Requirements

- Herdr 0.9.0 or newer
- `git`, `fzf`, and optionally `jq` (used to read the invocation context and to
  print Herdr's error message). fzf 0.63 or newer draws the bottom status bar.

## Install

Link the working directory, since this is a local plugin:

```bash
herdr plugin link ~/code/herdr-worktree-from
```

Bind a key in `config.toml`:

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
`bin/picker.sh` runs `fzf` over `git for-each-ref refs/heads refs/remotes`
with `--print-query`, skipping remote `HEAD` entries. It then calls one of:

```bash
herdr worktree create --cwd <repo> --branch <branch> --label <branch> --focus
herdr worktree create --cwd <repo> --branch <short> --base <remote ref> --focus
herdr worktree create --cwd <repo> --base <ref> --branch <name> --focus
```

The first opens a worktree on an existing local branch. The second creates a
local branch from a remote-only branch. The third is used when a name is
needed: a branch that is already checked out, a remote branch whose short name
is taken, or a query that matched nothing with `HEAD` as the base. Herdr
resolves the repository, checks the branch out or creates it from the base, and
opens or focuses the workspace.

## Debugging

```bash
bin/picker.sh --list       # candidate refs, no UI
bin/picker.sh --dry-run    # pick a branch, then print the herdr command only
herdr plugin log list --plugin worktree-from
```
