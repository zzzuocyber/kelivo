#!/usr/bin/env bash
# 上游排查：只算不改。
#
# 回答一个问题：如果把上游 master 全量合进来，哪些文件会打架、各自几处？
# 全部在内存里算（git merge-tree），不切分支、不动工作区、不写业务文件。
#
# 用法：
#   tool/upstream_triage.sh                    # 基线与上游都用默认
#   tool/upstream_triage.sh <基线提交>          # 手动指定基线
#   UPSTREAM_REMOTE=upstream/main tool/upstream_triage.sh
#
# 前置：先拉一次上游（带代理）
#   git -c http.proxy=http://127.0.0.1:7897 fetch upstream master --no-tags
#
# 判断标准：
#   0 处        → 全自动，直接合
#   1~5 处      → 手改几下
#   5 处以上    → 先看这个功能你用不用；自己重写过的文件（如迷你地图）建议整份保留自己的

set -uo pipefail

UPSTREAM="${UPSTREAM_REMOTE:-upstream/master}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "这里不是 git 仓库。" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "$UPSTREAM" >/dev/null; then
  echo "找不到 $UPSTREAM。先拉一次：" >&2
  echo "  git -c http.proxy=http://127.0.0.1:7897 fetch upstream master --no-tags" >&2
  exit 1
fi

BASE="${1:-$(git merge-base HEAD "$UPSTREAM")}"
COUNT=$(git rev-list --count "$BASE..$UPSTREAM")
FILES=$(git diff --name-only "$BASE" "$UPSTREAM" | wc -l | tr -d ' ')

echo
echo "=== 上游排查（只读，不改任何文件）==="
git log -1 --pretty="上游最新：%h  %ad  %s" --date=short "$UPSTREAM"
echo "距基线 ${BASE:0:8}：${COUNT} 个提交，${FILES} 个文件"
echo

if [ "$COUNT" -eq 0 ]; then
  echo "没有新提交，已经是最新。"
  exit 0
fi

# ---------- 一、会冲突的文件 ----------
TREE=$(git merge-tree --write-tree --name-only HEAD "$UPSTREAM" 2>/dev/null | head -1)
CONFLICTED=$(git merge-tree --write-tree --name-only HEAD "$UPSTREAM" 2>/dev/null |
  sed -n '2,/^$/p' | sed '/^$/d')

if [ -z "$CONFLICTED" ]; then
  echo "--- 会冲突的文件 ---"
  echo "没有。${COUNT} 个提交可以全部自动合进来。"
  echo
else
  TOTAL=0
  ROWS=$(
    for f in $CONFLICTED; do
      n=$(git cat-file -p "${TREE}:${f}" 2>/dev/null | grep -c '^<<<<<<<')
      printf '%s\t%s\n' "$n" "$f"
    done | sort -rn
  )
  while IFS=$'\t' read -r n _; do
    [ -n "${n:-}" ] && TOTAL=$((TOTAL + n))
  done <<<"$ROWS"
  echo "--- 会冲突的文件（共 ${TOTAL} 处）---"
  printf '处数  文件\n'
  while IFS=$'\t' read -r n f; do
    [ -n "${n:-}" ] && printf '%4s  %s\n' "$n" "$f"
  done <<<"$ROWS"
  echo
  echo "提示：超过 5 处的值得先看看这个功能你用不用；自己整页重写过的文件建议保留自己的。"
  echo
fi

# ---------- 二、碰到你改过的文件的提交 ----------
# 本地化文件每条提交都会加几条文案，算进「重合文件」只会把数字撑大，排除掉。
OURS=$(git diff --name-only "$BASE" HEAD | sed '\#^lib/l10n/#d')
echo "--- 碰到你改过的文件的提交（不算文案文件）---"
git log --reverse --name-only --pretty="COMMIT|%h|%ad|%s" --date=short "$BASE..$UPSTREAM" |

awk -v ours="$OURS" '
BEGIN {
  n = split(ours, arr, "\n")
  for (i = 1; i <= n; i++) if (arr[i] != "") mine[arr[i]] = 1
  hit = 0; files = 0; head = ""
}
/^COMMIT\|/ {
  if (head != "" && files > 0) { printf "%-9s %2d 个文件  %s\n", sha, files, subj; hit++ }
  split($0, p, "|"); sha = p[2]; subj = p[4]
  files = 0; head = "x"
  next
}
{
  if ($0 in mine) files++
}
END {
  if (head != "" && files > 0) { printf "%-9s %2d 个文件  %s\n", sha, files, subj; hit++ }
  printf "\n合计：%d 个提交碰到你改过的文件。\n", hit
}
'

echo "说明："
echo "  1) 第一张表才是要动手的地方，没列出来的文件都能自动合；"
echo "  2) 第二张表只是参考——碰到同一个文件不等于会冲突；"
echo "  3) 真要合的时候开临时分支，编过了再并回 master。"
echo
