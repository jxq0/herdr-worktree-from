# herdr-worktree-from

A Herdr plugin that creates a Git worktree, but asks which branch to base it on
first. The picker lists local and remote branches together, sorts them by commit
date, and filters as you type.

Press `prefix+ctrl+g` and type a few letters to filter:

```text
基准分支 > fea
+ 新建分支（基于当前 HEAD）  当前   2 days ago
feature/foo                  本地   2 days ago
origin/feature-bar          远端   3 weeks ago
```

The first row starts a brand-new branch at the current commit, so no existing
branch has to be picked. Every other row is an existing base branch.

Enter on a row, optionally name the new branch, and Herdr creates the workspace
and checkout. Leave the name empty to let Herdr generate
`worktree/<adjective>-<noun>-<hex>`. Selecting a remote branch whose short name
is not taken locally pre-fills that short name, so `origin/feature-x` becomes a
local `feature-x` based on the remote tip. Every path creates a new branch; the
plugin never checks an existing one out.

## Requirements

- Herdr 0.9.0 or newer
- `git`, `fzf`, and optionally `jq` (used to read the invocation context and to
  print Herdr's error message)

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
`bin/picker.sh` runs `fzf` over `git for-each-ref refs/heads refs/remotes`,
skips remote `HEAD` entries, and prepends a row whose ref is `HEAD` so a
brand-new branch can start at the current commit. It then calls:

```bash
herdr worktree create --cwd <repo> --base <picked ref> [--branch <name>] --focus
```

Herdr resolves the repository, checks whether the branch name already exists
locally, creates the checkout under its worktree directory, and opens or focuses
the workspace. Because the plugin passes `--base`, the new branch starts at the
picked ref; when the name is empty Herdr generates the branch name instead.

An existing local branch name is refused on purpose: Herdr would check that
branch out instead of creating a new one from the picked base, which is a
different operation. Use `herdr worktree open --branch <name>` for that.

## Debugging

```bash
bin/picker.sh --list       # candidate refs, no UI
bin/picker.sh --dry-run    # pick and name, then print the herdr command only
herdr plugin log list --plugin worktree-from
```
