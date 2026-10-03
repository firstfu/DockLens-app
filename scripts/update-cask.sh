#!/bin/zsh
# update-cask.sh：發佈新版本後，把 Homebrew tap（firstfu/homebrew-tap）的 cask 改成最新版本與雜湊並推送。
# 用法：先 scripts/package.sh release 並建立 GitHub release，再執行 scripts/update-cask.sh
# 為什麼用公開下載的檔案算雜湊：cask 的 sha256 必須是使用者實際下載到的檔案，不是本機打包的檔案。
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(defaults read "$PWD/DockLens/Resources/Info.plist" CFBundleShortVersionString)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/DockLens.zip" "https://github.com/firstfu/DockLens-app/releases/download/v$VERSION/DockLens.zip"
SHA=$(shasum -a 256 "$TMP/DockLens.zip" | cut -d' ' -f1)
gh repo clone firstfu/homebrew-tap "$TMP/tap" -- --depth 1 -q
cd "$TMP/tap"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/docklens.rb
git diff --stat
git commit -qam "DockLens $VERSION"
git push -q
echo "cask 已更新到 $VERSION（sha256 $SHA）"
