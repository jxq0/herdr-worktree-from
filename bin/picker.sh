#!/usr/bin/env bash
# Pick a branch, then open a worktree for it.
#
# - Lists local and remote branches (remotes as origin/xxx), newest first.
# - Type to filter, arrow keys to move, Enter to select, Esc to cancel.
# - Enter opens a worktree on the picked branch. A local branch is used as is; a
#   remote branch becomes a local branch with the same short name based on the
#   remote tip, or reuses the local branch when one already has that name.
# - alt-enter asks for a new branch name, then opens a worktree on that new
#   branch, created from the picked ref.
# - When the query matches nothing, neither key does anything: the picker stays
#   open until the query matches or Esc is pressed.
# - Creation goes through herdr worktree create; the workspace, checkout path
#   and focus stay with herdr.
#
# Requires: git and fzf. jq is optional, used for the invocation context and
# for printing herdr's error message.
# Debug: --list prints the candidates; --dry-run prints the herdr command.
#
# fzf has no ctrl-enter key, so the second action is alt-enter.

set -uo pipefail

mode="run"
case "${1:-}" in
  --list) mode="list" ;;
  --dry-run) mode="dry" ;;
esac

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
has_jq=0
command -v jq >/dev/null 2>&1 && has_jq=1

fail() {
  printf '\n%s\n\nPress any key to close...' "$1" >&2
  read -r -n 1 -s || true
  exit 1
}

ctx_field() {
  [[ $has_jq -eq 1 && -n "$ctx" ]] || return 0
  printf '%s' "$ctx" | jq -r "$1 // empty" 2>/dev/null
}

# Prefer the repo_root from herdr: when the current workspace is itself a
# linked worktree, it points at the main repository instead of that checkout.
resolve_repo() {
  local candidate top
  for candidate in \
    "$(ctx_field '.worktree.repo_root')" \
    "$PWD" \
    "$(ctx_field '.focused_pane_cwd')" \
    "$(ctx_field '.workspace_cwd')"
  do
    [[ -n "$candidate" ]] || continue
    top=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null) || continue
    printf '%s\n' "$top"
    return 0
  done
  return 1
}

repo=$(resolve_repo) || fail "Not inside a Git repository and no pane cwd is available"
cd "$repo" || fail "Cannot enter $repo"

list_refs() {
  git for-each-ref --sort=-committerdate \
    --format=$'%(refname:short)\tlocal\t%(committerdate:relative)' refs/heads
  git for-each-ref --sort=-committerdate \
    --format=$'%(refname:short)\tremote\t%(committerdate:relative)' refs/remotes |
    while IFS=$'\t' read -r ref type age; do
      [[ "$ref" == */HEAD ]] && continue
      printf '%s\t%s\t%s\n' "$ref" "$type" "$age"
    done
}

refs=$(list_refs)
[[ -n "$refs" ]] || fail "Repository $repo has no branches yet"

if [[ "$mode" == "list" ]]; then
  printf '%s\n' "$refs"
  exit 0
fi

command -v fzf >/dev/null 2>&1 || fail "fzf is required: brew install fzf"

current=$(git symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')
repo_name=${repo##*/}
local_count=$(printf '%s\n' "$refs" | LC_ALL=C awk -F'\t' '$2 == "local" { n++ } END { print n + 0 }')
remote_count=$(printf '%s\n' "$refs" | LC_ALL=C awk -F'\t' '$2 == "remote" { n++ } END { print n + 0 }')
footnote="repo ${repo_name} · branch ${current} · ${local_count} local · ${remote_count} remote"$'\n'"Enter: worktree on this branch · alt-enter: new branch from it · Esc: cancel"

# --footer exists since fzf 0.63. Older versions get the same text as a header.
has_footer=0
fzf --help 2>/dev/null | grep -q -- '--footer' && has_footer=1

# alt-enter touches a file so the script can tell the two keys apart after fzf
# exits. --expect cannot be used here: it takes precedence over --bind, so it
# would also close the picker on alt-enter when nothing matches.
action_file=$(mktemp /tmp/worktree-from.XXXXXX)
rm -f "$action_file"
trap 'rm -f "$action_file"' EXIT

fzf_args=(
  --delimiter=$'\t'
  --with-nth=1,2,3
  --info=inline-right
  --no-separator
  --prompt='Branch > '
  --height=100%
  --layout=reverse
  --tabstop=4
  --no-multi
  --cycle
  --tiebreak=index
  --pointer='▸'
  --preview='git -C "$REPO" log --oneline --decorate --graph -12 {1} 2>&1'
  --preview-window='right,50%,border-left'
  --bind='enter:transform:[[ -n {} ]] && echo accept || echo bell'
  --bind="alt-enter:transform:[[ -n {} ]] && echo 'execute-silent(touch $action_file)+accept' || echo bell"
)

if [[ $has_footer -eq 1 ]]; then
  fzf_args+=(--footer="$footnote" --footer-border=line --color=footer:8)
else
  fzf_args+=(--header="$footnote")
fi

fzf_out=$(
  printf '%s\n' "$refs" |
    REPO="$repo" fzf "${fzf_args[@]}"
)
fzf_status=$?
[[ $fzf_status -eq 130 ]] && exit 0
selected=$(printf '%s\n' "$fzf_out" | sed -n '1p')
[[ -n "$selected" ]] || exit 0

ref=$(printf '%s' "$selected" | cut -f1)
type=$(printf '%s' "$selected" | cut -f2)

new_branch=""
if [[ -e "$action_file" ]]; then
  printf 'New branch name based on %s [empty line to cancel]: ' "$ref"
  IFS= read -r -e new_branch || true
  new_branch="${new_branch#"${new_branch%%[![:space:]]*}"}"
  new_branch="${new_branch%"${new_branch##*[![:space:]]}"}"
  if [[ -z "$new_branch" ]]; then
    printf '%s\n' 'Cancelled; nothing was created.'
    exit 0
  fi
  git check-ref-format --branch "$new_branch" >/dev/null 2>&1 ||
    fail "Invalid branch name: $new_branch"
  if git show-ref --verify --quiet "refs/heads/$new_branch"; then
    fail "Branch ${new_branch} already exists locally; choose another name"
  fi
fi

if [[ -n "$new_branch" ]]; then
  args=(worktree create --cwd "$repo" --base "$ref" --branch "$new_branch" --label "$new_branch" --focus)
elif [[ "$type" == "remote" ]]; then
  short=${ref#*/}
  if git show-ref --verify --quiet "refs/heads/$short"; then
    args=(worktree create --cwd "$repo" --branch "$short" --label "$short" --focus)
  else
    args=(worktree create --cwd "$repo" --branch "$short" --label "$short" --base "$ref" --focus)
  fi
else
  args=(worktree create --cwd "$repo" --branch "$ref" --label "$ref" --focus)
fi

if [[ "$mode" == "dry" ]]; then
  printf '\nWould run: '
  printf '%q ' "$herdr_bin" "${args[@]}"
  printf '\nPress any key to close...'
  read -r -n 1 -s || true
  exit 0
fi

output=$("$herdr_bin" "${args[@]}" 2>&1)
status=$?

if [[ $has_jq -eq 1 ]] && printf '%s' "$output" | jq -e '.error' >/dev/null 2>&1; then
  fail "Could not create the worktree: $(printf '%s' "$output" | jq -r '.error.message // "unknown error"')"
fi

if [[ $status -ne 0 ]]; then
  fail "Could not create the worktree: ${output:-herdr worktree create exited with status $status}"
fi

exit 0
