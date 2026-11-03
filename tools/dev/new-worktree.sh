#!/bin/bash
# 为某个平台创建独立 git worktree（同一仓库、不同分支、不同工作目录）
# 用法： tools/dev/new-worktree.sh windows
set -euo pipefail
PLATFORM="${1:?usage: new-worktree.sh <android|windows|linux|macos|ios>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$(dirname "$ROOT")/wildlime-$PLATFORM"
BRANCH="platform/$PLATFORM"

cd "$ROOT"
if git worktree list | grep -q " $DEST "; then
  echo "worktree already exists: $DEST"; exit 0
fi
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git worktree add "$DEST" "$BRANCH"
else
  git worktree add -b "$BRANCH" "$DEST" main
fi
echo "created: $DEST  (branch $BRANCH)"
echo "在该目录里开工，提交前缀用 '${PLATFORM}:'"
