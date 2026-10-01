#!/bin/zsh
# orientation-test.sh：暫時把 Dock 移到左側、右側各跑一次完整自我測試（含 Dock 重啟接回），
# 結果存到 ~/Library/Caches/com.firstfu.DockLens/orientation/<方向>/。
# 不論成功或中斷，結束時一律還原原本的 Dock 位置。
set -u
cd "$(dirname "$0")/.."
ORIGINAL=$(defaults read com.apple.dock orientation 2>/dev/null || echo bottom)
DEST=~/Library/Caches/com.firstfu.DockLens/orientation
restore() {
  defaults write com.apple.dock orientation -string "$ORIGINAL"
  killall Dock
  echo "已還原 Dock 位置：$ORIGINAL"
}
trap restore EXIT INT TERM
rm -rf $DEST; mkdir -p $DEST
[ $# -eq 0 ] && set -- left right
for side in "$@"; do
  echo "===== Dock 位置：$side ====="
  defaults write com.apple.dock orientation -string $side
  killall Dock
  sleep 3
  scripts/selftest.sh Debug --restart-dock | tail -32
  mkdir -p $DEST/$side
  cp ~/Library/Caches/com.firstfu.DockLens/selftest/* $DEST/$side/ 2>/dev/null
done
