#!/bin/zsh
# install.sh：建置 Release、安裝到 /Applications 並註冊開機啟動
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project DockLens.xcodeproj -scheme DockLens -configuration Release -derivedDataPath build -destination 'platform=macOS' build -quiet
pkill -x DockLens || true
sleep 0.5
ditto build/Build/Products/Release/DockLens.app /Applications/DockLens.app
codesign --verify --deep --strict /Applications/DockLens.app
open /Applications/DockLens.app --args --register-login-item
echo "已安裝 /Applications/DockLens.app 並設定開機啟動"
