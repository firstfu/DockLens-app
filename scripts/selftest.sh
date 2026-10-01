#!/bin/zsh
# selftest.sh：建置 DockLens 與測試用 DockLensFixture，以 open 啟動端到端自我測試
# （讓 TCC 以 DockLens 自身身分判斷權限），同步錄下日誌並印出結果摘要。
# 測試期間會暫停已安裝的 DockLens（避免兩個面板互相干擾），結束後自動重新啟動。
# 用法：scripts/selftest.sh [Debug|Release] [額外參數，例如 --restart-dock]
set -u
cd "$(dirname "$0")/.."
CONFIG=${1:-Debug}
shift 2>/dev/null
EXTRA=("$@")
APP=build/Build/Products/$CONFIG/DockLens.app
FIXTURE=$PWD/build/Build/Products/Debug/DockLensFixture.app
OUT=~/Library/Caches/com.firstfu.DockLens/selftest
LOG=/tmp/docklens-selftest.log

for scheme in DockLens DockLensFixture; do
  cfg=$CONFIG; [ $scheme = DockLensFixture ] && cfg=Debug
  xcodebuild -project DockLens.xcodeproj -scheme $scheme -configuration $cfg -derivedDataPath build \
    -destination 'platform=macOS' build -quiet 2>&1 | grep -E "error:" && exit 1
done

INSTALLED_WAS_RUNNING=0
pgrep -f "/Applications/DockLens.app/Contents/MacOS/DockLens" >/dev/null && INSTALLED_WAS_RUNNING=1
pkill -x DockLens; sleep 0.5

/usr/bin/log stream --predicate 'subsystem == "com.firstfu.DockLens"' --level debug --style compact > $LOG 2>&1 &
LOGPID=$!
sleep 1
open -n "$APP" --args --selftest --fixture "$FIXTURE" "${EXTRA[@]}"
for i in $(seq 1 180); do sleep 1; pgrep -f "$APP/Contents/MacOS/DockLens" >/dev/null || break; done
sleep 1; kill $LOGPID 2>/dev/null

[ $INSTALLED_WAS_RUNNING = 1 ] && open /Applications/DockLens.app

sed -E 's/^[0-9-]+ ([0-9:.]+) +[A-Za-z]+ +DockLens\[[0-9:a-f]+\] /\1 /' $LOG | grep -v "^Filtering\|^Timestamp" > /tmp/docklens-selftest-clean.log
python3 - "$OUT/report.json" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
print(f"=== 自我測試：通過 {r['passed']}、失敗 {r['failed']}（登入項目 {r['loginItemStatus']}、峰值記憶體 {r['peakMemoryMB']}MB）")
for c in r["checks"]:
    print(("✅ " if c["passed"] else "❌ ") + c["name"] + (f"（{c['detail']}）" if c["detail"] else ""))
print("--- 延遲（hover 事件起算，含懸停延遲 %dms）" % r["hoverDelayMs"])
for s in r["samples"]:
    print(f"{s['app']:<22} 視窗 {s['windows']}  面板 {s.get('showLatencyMs')}ms  縮圖就緒 {s.get('thumbnailsReadyMs')}ms")
EOF
