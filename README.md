# DockLens

**Hover a Dock icon, see every window of that app.** Click a thumbnail to switch, or close / minimize / full-screen it right from the preview.

游標停在 Dock 圖示上，就能看到這個 App 的所有視窗縮圖；點縮圖直接切換，也能在預覽上關閉、縮小、全螢幕。（中文說明在下方）

> **Free public beta.** I'm building this on my own and want to learn what you actually need — please open an [Issue](../../issues/new/choose) with bugs or ideas.

<!-- 示範動圖：docs/demo.gif（待錄製） -->

## Features

- Live thumbnails of all windows when you hover a Dock icon; click to switch
- Traffic-light buttons on each thumbnail: close, minimize / restore, full screen
- Header actions: new window, hide app, quit app
- Shows minimized windows and windows on other Spaces
- Windows you closed with ✕ while the app keeps running (Notion, Slack…) stay listed — click to reopen
- Dock on bottom, left or right; works with auto-hide, magnification and multiple displays

## Performance (Apple silicon, measured)

| | |
|---|---|
| Hover → preview | ~125–140 ms (includes an adjustable 120 ms hover delay) |
| Idle | 0% CPU, 0 wakeups, ~20–30 MB memory |

Event-driven — nothing polls while you're not using it.

## Privacy

DockLens makes **no network connections at all**. Thumbnails are captured and shown locally and never leave your Mac.

## Requirements

macOS 26 or later.

## Install

1. Download `DockLens.zip` from [Releases](../../releases/latest) and unzip it.
2. Move `DockLens.app` to `/Applications`.
3. Open it. macOS will block it the first time, because this beta isn't notarized by Apple yet:
   - Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to "DockLens was blocked".
4. Grant the two permissions the onboarding asks for:
   - **Accessibility** — to know which Dock icon you're hovering and to switch / close windows
   - **Screen Recording** — to capture window thumbnails (local only)

---

## 中文說明

**免費公開測試版。**這是我一個人開發的小工具，想知道大家真正需要什麼——有問題或想要的功能，請開 [Issue](../../issues/new/choose) 告訴我。

### 功能

- 游標停在 Dock 圖示上，即時顯示該 App 所有視窗的縮圖，點縮圖切換
- 縮圖上的紅黃綠按鈕：關閉、縮到 Dock／還原、全螢幕
- 標頭：開新視窗、隱藏 App、結束 App
- 會列出已縮小的視窗、其他桌面（Space）上的視窗
- 按 ✕ 關掉但 App 還開著的視窗（Notion、Slack 等）會保留在預覽裡，點一下重新打開
- Dock 放底部、左側、右側都能用；支援自動隱藏、放大效果、多螢幕

### 隱私

DockLens **完全不連網**。縮圖只在你的 Mac 上擷取與顯示，不會上傳。

### 系統需求

macOS 26 以上。

### 安裝

1. 從 [Releases](../../releases/latest) 下載 `DockLens.zip` 並解壓縮
2. 把 `DockLens.app` 拖進「應用程式」資料夾
3. 打開它。第一次會被系統擋下（測試版還沒經過 Apple 公證）：
   到 **系統設定 → 隱私權與安全性**，往下捲，在「已阻擋 DockLens」旁按 **強制打開**
4. 依引導開啟兩個權限：
   - **輔助使用**：偵測游標停在哪個 Dock 圖示、切換與關閉視窗
   - **螢幕錄製**：擷取視窗縮圖（只在本機處理）
