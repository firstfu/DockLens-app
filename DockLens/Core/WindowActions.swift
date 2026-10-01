//
//  WindowActions.swift
//  DockLens
//
//  對視窗/App 的操作：切換到視窗、關閉、縮小、隱藏、結束。
//  切換視窗優先走 SkyLight 私有 API（可指定視窗、可跨 Space），失敗才退回公開 API。
//

import AppKit

enum WindowActions {
    /// 切換到指定視窗：取消最小化 → 前置 App 並讓該視窗成為 key → AXRaise 確保它在同 App 視窗的最上層。
    /// 其他桌面（Space）上的視窗沒有一般的 AX 元素，改以 remote token 找出來：少了 AXRaise 這一步，
    /// App 會到前景但畫面不會切到視窗所在的 Space（見 `AXRemote`）。
    /// - Parameter window: 目標視窗
    static func focus(_ window: WindowInfo) {
        let element = window.ax?.element
            ?? (window.isOnOtherSpace ? AXRemote.windowElement(pid: window.pid, windowID: window.id) : nil)
        // 被 ⌘H 隱藏的 App 要先取消隱藏，視窗才會出現
        if let app = NSRunningApplication(processIdentifier: window.pid), app.isHidden { app.unhide() }
        if window.isMinimized {
            element?.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        if !SkyLight.focus(pid: window.pid, windowID: window.id) {
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        element?.perform(kAXRaiseAction)
        element?.set(kAXMainAttribute, kCFBooleanTrue)
    }

    /// 重新打開 App：等同點 Dock 圖示（LaunchServices 會啟用 App 並送出「重新打開」事件），
    /// 按 X 只把主視窗藏起來的 App（Notion、Slack 等）收到後會把視窗叫回來。
    /// - Parameter app: 目標 App
    static func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("DockLens 重新打開 App 失敗：\(error.localizedDescription)") }
        }
    }

    /// 關閉視窗：按下視窗的關閉鈕（等同使用者點紅燈，App 可以跳出「是否儲存」）。
    /// - Returns: 是否成功送出
    @discardableResult
    static func close(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element,
              let button: AXUIElement = element.value(kAXCloseButtonAttribute) else { return false }
        return button.perform(kAXPressAction)
    }

    /// 切換最小化狀態。
    /// - Returns: 是否成功
    @discardableResult
    static func toggleMinimize(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element else { return false }
        return element.set(kAXMinimizedAttribute, window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// 切換全螢幕。
    @discardableResult
    static func toggleFullScreen(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element else { return false }
        let current: Bool = element.value("AXFullScreen") ?? false
        return element.set("AXFullScreen", current ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// 隱藏或顯示 App。
    static func toggleHidden(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() } else { app.hide() }
    }

    /// 開新視窗：啟用 App 後對它送出 ⌘N（絕大多數 App 的「新增視窗」快捷鍵）。
    /// 直接把按鍵事件投遞給該 pid，不會誤觸其他 App。
    static func newWindow(_ app: NSRunningApplication) {
        app.unhide()
        app.activate()
        let pid = app.processIdentifier
        Task { @MainActor in
            // 等 App 成為前景再送鍵，否則部分 App 會忽略
            try? await Task.sleep(for: .milliseconds(120))
            let source = CGEventSource(stateID: .hidSystemState)
            let keyN: CGKeyCode = 45
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyN, keyDown: isDown)
                event?.flags = .maskCommand
                event?.postToPid(pid)
            }
        }
    }

    /// 結束 App（正常結束，App 可詢問是否存檔）。
    static func quit(_ app: NSRunningApplication) {
        app.terminate()
    }
}
