#!/usr/bin/env bash
# 选一个基准分支，再创建基于它的新 worktree。
#
# - 列表同时包含本地分支和远程分支，远端显示成 origin/xxx，按提交时间倒序。
# - 输入任意字符过滤，方向键移动，回车选择，Esc 取消。
# - 选完可以输入新分支名；留空则让 herdr 生成 worktree/<形容词>-<名词>-<hex>。
# - 创建交给 herdr worktree create --base，workspace、checkout 路径、焦点都由 herdr 管。
#
# 依赖：git、fzf；jq 可选，用于读 HERDR_PLUGIN_CONTEXT_JSON 和解析错误。
# 调试：--list 只打印候选分支；--dry-run 打印将要执行的 herdr 命令而不创建。

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
  printf '\n%s\n\n按任意键关闭…' "$1" >&2
  read -r -n 1 -s || true
  exit 1
}

ctx_field() {
  [[ $has_jq -eq 1 && -n "$ctx" ]] || return 0
  printf '%s' "$ctx" | jq -r "$1 // empty" 2>/dev/null
}

# 优先用 herdr 给的 repo_root：当前 workspace 本身是 worktree 时，它指向主仓库，
# 而不是那份 checkout。
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

repo=$(resolve_repo) || fail "当前目录不在 Git 仓库里，也没有可用的 pane cwd"
cd "$repo" || fail "进不去 $repo"

list_refs() {
  git for-each-ref --sort=-committerdate \
    --format=$'%(refname:short)\t本地\t%(committerdate:relative)' refs/heads
  git for-each-ref --sort=-committerdate \
    --format=$'%(refname:short)\t远端\t%(committerdate:relative)' refs/remotes |
    while IFS=$'\t' read -r ref type age; do
      [[ "$ref" == */HEAD ]] && continue
      printf '%s\t%s\t%s\n' "$ref" "$type" "$age"
    done
}

refs=$(list_refs)
[[ -n "$refs" ]] || fail "仓库 $repo 里还没有任何分支"

if [[ "$mode" == "list" ]]; then
  printf '%s\n' "$refs"
  exit 0
fi

command -v fzf >/dev/null 2>&1 || fail "需要 fzf：brew install fzf"

current=$(git symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')
repo_name=${repo##*/}

selected=$(
  printf '%s\n' "$refs" |
    REPO="$repo" fzf \
      --delimiter=$'\t' \
      --with-nth=1,2,3 \
      --prompt='基准分支 > ' \
      --header=$'仓库 '"$repo_name"'  当前 '"$current"$'\n回车选择 · 输入过滤 · Esc 取消' \
      --height=100% \
      --layout=reverse \
      --tabstop=4 \
      --no-multi \
      --cycle \
      --tiebreak=index \
      --pointer='▸' \
      --preview='git -C "$REPO" log --oneline --decorate --graph -12 {1} 2>&1' \
      --preview-window='right,50%,border-left'
)
[[ -n "$selected" ]] || exit 0

ref=${selected%%$'\t'*}
type=$(printf '%s' "$selected" | cut -f2)

# 选的是远端分支、本地又没有同名分支时，新分支名默认就用它的短名，
# 相当于把 origin/feature-x 落成本地 feature-x。
default=""
if [[ "$type" == "远端" ]]; then
  short=${ref#*/}
  if [[ -n "$short" ]] && ! git show-ref --verify --quiet "refs/heads/$short"; then
    default=$short
  fi
fi

printf '基于 %s 新建 worktree\n' "$ref"
if [[ -n "$default" ]]; then
  printf '新分支名 [回车用 %s]: ' "$default"
else
  printf '新分支名 [回车让 herdr 自动生成]: '
fi
IFS= read -r -e new_branch || true
new_branch="${new_branch#"${new_branch%%[![:space:]]*}"}"
new_branch="${new_branch%"${new_branch##*[![:space:]]}"}"
[[ -z "$new_branch" ]] && new_branch=$default

if [[ -n "$new_branch" ]]; then
  git check-ref-format --branch "$new_branch" >/dev/null 2>&1 ||
    fail "分支名不合法：$new_branch"
  if git show-ref --verify --quiet "refs/heads/$new_branch"; then
    fail "本地已经有分支 ${new_branch}，换一个名字（这个插件只用来新建 worktree）"
  fi
fi

args=(worktree create --cwd "$repo" --base "$ref" --focus)
if [[ -n "$new_branch" ]]; then
  args+=(--branch "$new_branch" --label "$new_branch")
fi

if [[ "$mode" == "dry" ]]; then
  printf '\n将执行：'
  printf '%q ' "$herdr_bin" "${args[@]}"
  printf '\n按任意键关闭…'
  read -r -n 1 -s || true
  exit 0
fi

output=$("$herdr_bin" "${args[@]}" 2>&1)
status=$?

if [[ $has_jq -eq 1 ]] && printf '%s' "$output" | jq -e '.error' >/dev/null 2>&1; then
  fail "创建失败：$(printf '%s' "$output" | jq -r '.error.message // "未知错误"')"
fi

if [[ $status -ne 0 ]]; then
  fail "创建失败：${output:-herdr worktree create 退出码 $status}"
fi

exit 0
