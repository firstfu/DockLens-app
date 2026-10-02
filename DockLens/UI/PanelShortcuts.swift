//
//  PanelShortcuts.swift
//  DockLens
//
//  預覽面板的單鍵快捷鍵：游標停在面板上時按 W 關閉、M 縮小／還原（作用於游標所在的卡片）、
//  H 隱藏、Q 結束（作用於整個 App）。
//
//  為什麼用 CGEventTap 而不是讓面板成為 key window：
//  - 面板刻意不搶焦點（見 `PreviewPanel`），成為 key window 會讓前景 App 的視窗失去焦點、標題列閃動。
//  - NSEvent 的全域監聽只能「看」不能「攔」，按下的 W 仍會打進前景 App 的文件裡。
//  主動式 event tap 可以吃掉這幾個鍵，只需要已經取得的「輔助使用」權限（公開 API，不需私有 API）。
//  tap 只在面板顯示期間啟用，閒置時停用，維持零成本。
//

import AppKit

/// 面板上的單鍵動作。
nonisolated enum PanelShortcut: Equatable, Sendable {
    case close
    case minimize
    case hide
    case quit

    /// 依按鍵字元與修飾鍵判斷是哪個快捷鍵。
    /// 以字元（而非實體鍵碼）判斷，AZERTY 等非 QWERTY 配置下按的才會是印在鍵帽上的那個字母。
    /// - Parameters:
    ///   - characters: 忽略修飾鍵後的字元（`charactersIgnoringModifiers`）
    ///   - flags: 按下時的修飾鍵
    /// - Returns: 對應的快捷鍵；有 ⌘／⌃／⌥ 或不是這四個字母時為 nil（保留給前景 App，例如 ⌘W、⌘Q）
    static func match(characters: String?, flags: CGEventFlags) -> PanelShortcut? {
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let characters, characters.count == 1 else { return nil }
        switch characters.lowercased() {
        case "w": return .close
        case "m": return .minimize
        case "h": return .hide
        case "q": return .quit
        default: return nil
        }
    }
}

/// 包裝一個鍵盤 CGEventTap：由 `handler` 決定每次按鍵要不要吃掉。
/// tap 建立一次後重複使用，以 `isEnabled` 開關（停用中的 tap 不會收到任何事件）。
final class PanelKeyInterceptor {
    /// 收到按下事件時呼叫；回傳 true 表示吃掉這個按鍵（前景 App 不會收到）。
    /// 參數：快捷鍵、是否為按住不放的自動重複。
    var handler: (PanelShortcut, Bool) -> Bool = { _, _ in false }

    private var tap: CFMachPort?
    /// 已吃掉 keyDown 的鍵碼：對應的 keyUp 也要吃掉，前景 App 才不會收到落單的放開事件
    private var swallowedKeyCodes: Set<Int64> = []

    /// 啟用或停用攔截。第一次啟用時才建立 tap；沒有輔助使用權限時建立會失敗，此時快捷鍵單純無效。
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled && tap == nil { createTap() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: isEnabled) }
            if !isEnabled { swallowedKeyCodes.removeAll() }
        }
    }

    private func createTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                // source 掛在主執行緒的 run loop 上，回呼必定在主執行緒
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<PanelKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("DockLens 無法建立鍵盤 event tap（缺少輔助使用權限？），單鍵快捷鍵停用")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
    }

    /// - Returns: 是否吃掉這個事件
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系統判定回呼太慢或使用者輸入時會停用 tap；仍在使用中就重新啟用
            if isEnabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard let shortcut = PanelShortcut.match(
                characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers, flags: event.flags
            ) else { return false }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard handler(shortcut, isRepeat) else { return false }
            swallowedKeyCodes.insert(keyCode)
            return true
        case .keyUp:
            return swallowedKeyCodes.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        default:
            return false
        }
    }
}
