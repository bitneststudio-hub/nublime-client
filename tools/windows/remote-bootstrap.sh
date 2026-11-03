#!/bin/bash
# 在 Mac 上一键完成：同步仓库 → 拉运行时核心 → 构建 → 取回产物
#   WIN_HOST=happy@192.168.1.50 tools/windows/remote-bootstrap.sh
set -euo pipefail

HOST="${WIN_HOST:?用法: WIN_HOST=happy@<ip> $0}"
KEY="${WIN_KEY:-$HOME/.ssh/windows_deploy_ed25519}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REMOTE="$HOME/wildlime-sync.tgz"
WIN_DIR="${WIN_DIR:-C:/Users/happy/Projects/wildlime}"
SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

PS() { ssh "${SSH_OPTS[@]}" "$HOST" powershell -NoProfile -ExecutionPolicy Bypass -Command "$1"; }

echo "== 0/4 连通性"
ssh "${SSH_OPTS[@]}" "$HOST" "powershell -NoProfile -Command \"\$env:COMPUTERNAME + ' / ' + (whoami)\""

echo "== 1/4 打包并上传（排除 build/.git/.dart_tool）"
tar czf "$REMOTE" -C "$REPO" \
  --exclude='./.git' --exclude='./app/build' --exclude='./app/.dart_tool' \
  --exclude='./app/android/.gradle' --exclude='./app/ios/Pods' .
ls -lh "$REMOTE" | awk '{print "   " $5}'
scp -O -q -i "$KEY" "$REMOTE" "$HOST:wildlime-sync.tgz"

echo "== 2/4 解压到 $WIN_DIR"
PS "if (!(Test-Path '$WIN_DIR')) { New-Item -ItemType Directory -Path '$WIN_DIR' -Force | Out-Null }; tar -xzf \$env:USERPROFILE\wildlime-sync.tgz -C '$WIN_DIR'; '   files: ' + (Get-ChildItem '$WIN_DIR' -Recurse -File | Measure-Object).Count"

echo "== 3/4 拉运行时核心（xray.exe + wintun.dll，已存在则跳过）"
PS "if (Test-Path '$WIN_DIR\app\windows\core\xray.exe') { '   core already present' } else { & '$WIN_DIR\tools\windows\fetch_core.ps1' -Project '$WIN_DIR' }"

echo "== 4/4 构建"
PS "& '$WIN_DIR\tools\windows\build.ps1' -Project '$WIN_DIR'"

ART=$(PS "(Get-ChildItem '$WIN_DIR\app\dist\*.zip' | Sort-Object LastWriteTime | Select-Object -Last 1).FullName")
echo "   产物: $ART"
scp -O -q -i "$KEY" "$HOST:$ART" "$HOME/Downloads/" 
echo "== 完成，已取回 ~/Downloads/$(basename "$ART")"
