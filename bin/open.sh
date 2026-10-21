#!/usr/bin/env bash
# 打开选择基准分支的 popup。cwd 取当前 pane 所在仓库，这样 picker 不用猜路径。

set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
plugin_id="${HERDR_PLUGIN_ID:-worktree-from}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

cwd=""
if [[ -n "$ctx" ]] && command -v jq >/dev/null 2>&1; then
  cwd=$(printf '%s' "$ctx" | jq -r '.worktree.repo_root // .focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null)
fi

args=(plugin pane open --plugin "$plugin_id" --entrypoint picker --placement popup)
[[ -n "$cwd" ]] && args+=(--cwd "$cwd")

exec "$herdr_bin" "${args[@]}"
