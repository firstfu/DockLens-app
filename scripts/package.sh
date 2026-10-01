#!/bin/zsh
# package.sh：建置 Release 並打包成可公開下載的 DockLens.zip（未公證的測試版）
#
# 用法：scripts/package.sh [dev|adhoc]
#   dev   （預設）沿用 Config/Signing.xcconfig 的簽章（沒有 Signing.local.xcconfig 時即 ad-hoc）。
#          若用 Apple Development 憑證，更新版本後使用者的系統權限會保留，
#          但簽章裡帶有憑證持有人的姓名，任何人用 codesign 都看得到。
#   adhoc  重新以 ad-hoc 簽章，不含任何個人資訊；代價是每次更新後使用者要重新開啟
#          「輔助使用」與「螢幕錄製」權限（系統以程式碼雜湊辨識 ad-hoc 簽章的 App）。
#
# 產出：dist/DockLens.zip 與 dist/DockLens.zip.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=${1:-dev}
[[ $MODE == dev || $MODE == adhoc ]] || { echo "用法：$0 [dev|adhoc]"; exit 1; }

xcodebuild -project DockLens.xcodeproj -scheme DockLens -configuration Release -derivedDataPath build \
  -destination 'platform=macOS' build -quiet

rm -rf dist && mkdir -p dist
ditto build/Build/Products/Release/DockLens.app dist/DockLens.app
if [[ $MODE == adhoc ]]; then
  # --options runtime 保留 hardened runtime；entitlements 沿用原本的（目前為空）
  codesign --force --deep --options runtime --sign - \
    --entitlements DockLens/Resources/DockLens.entitlements dist/DockLens.app
fi
codesign --verify --deep --strict dist/DockLens.app

# ditto -c -k --keepParent：保留 bundle 結構與延伸屬性，Finder 解壓縮即為 DockLens.app
ditto -c -k --keepParent dist/DockLens.app dist/DockLens.zip
rm -rf dist/DockLens.app
shasum -a 256 dist/DockLens.zip | tee dist/DockLens.zip.sha256
echo "簽章方式：$MODE；產出 dist/DockLens.zip"
