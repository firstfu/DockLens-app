//
//  AppSettings.swift
//  DockLens
//
//  使用者設定：以 @Observable 提供 SwiftUI 綁定，每次修改即寫回 UserDefaults。
//

import Foundation
import Observation
import ServiceManagement

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// 總開關
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    /// 縮圖高度（points）
    var thumbnailHeight: Double { didSet { defaults.set(thumbnailHeight, forKey: Key.thumbnailHeight) } }
    /// 游標停在圖示上多久才顯示預覽（秒）；面板已顯示時切換圖示不再等待
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    /// 是否顯示視窗標題
    var showsTitles: Bool { didSet { defaults.set(showsTitles, forKey: Key.showsTitles) } }
    /// 是否納入其他桌面（Space）的視窗
    var includesOtherSpaces: Bool { didSet { defaults.set(includesOtherSpaces, forKey: Key.includesOtherSpaces) } }
    /// App 沒有開著的視窗時，是否列出「按 X 關掉但仍保留」的視窗（點擊重新打開）
    var showsClosedWindows: Bool { didSet { defaults.set(showsClosedWindows, forKey: Key.showsClosedWindows) } }
    /// App 沒有視窗時是否仍顯示提示面板
    var showsEmptyState: Bool { didSet { defaults.set(showsEmptyState, forKey: Key.showsEmptyState) } }

    /// 游標停在「行事曆」圖示上時顯示今天的行程
    var showsCalendarAgenda: Bool { didSet { defaults.set(showsCalendarAgenda, forKey: Key.showsCalendarAgenda) } }

    /// 游標停在面板上時可用單鍵操作（W 關閉、M 縮小、H 隱藏、Q 結束）
    var panelShortcuts: Bool { didSet { defaults.set(panelShortcuts, forKey: Key.panelShortcuts) } }
    /// 每週自動檢查有沒有新版本（會連到 GitHub；預設關閉，維持「不主動連網」的承諾）
    var autoChecksForUpdates: Bool { didSet { defaults.set(autoChecksForUpdates, forKey: Key.autoChecksForUpdates) } }
    /// 上次成功檢查更新的時間
    var lastUpdateCheck: Date? { didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) } }

    /// 開機自動啟動（直接讀寫 SMAppService，不另存）
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("DockLens 登入項目設定失敗：\(error.localizedDescription)")
                }
            }
        }
    }

    private enum Key {
        static let enabled = "enabled"
        static let thumbnailHeight = "thumbnailHeight"
        static let hoverDelay = "hoverDelay"
        static let showsTitles = "showsTitles"
        static let includesOtherSpaces = "includesOtherSpaces"
        static let showsEmptyState = "showsEmptyState"
        static let showsClosedWindows = "showsClosedWindows"
        static let showsCalendarAgenda = "showsCalendarAgenda"
        static let panelShortcuts = "panelShortcuts"
        static let autoChecksForUpdates = "autoChecksForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
    }

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.thumbnailHeight: 150.0,
            Key.hoverDelay: 0.12,
            Key.showsTitles: true,
            Key.includesOtherSpaces: true,
            Key.showsEmptyState: false,
            Key.showsClosedWindows: true,
            Key.showsCalendarAgenda: true,
            Key.panelShortcuts: true,
            Key.autoChecksForUpdates: false,
        ])
        isEnabled = defaults.bool(forKey: Key.enabled)
        thumbnailHeight = defaults.double(forKey: Key.thumbnailHeight)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        showsTitles = defaults.bool(forKey: Key.showsTitles)
        includesOtherSpaces = defaults.bool(forKey: Key.includesOtherSpaces)
        showsEmptyState = defaults.bool(forKey: Key.showsEmptyState)
        showsClosedWindows = defaults.bool(forKey: Key.showsClosedWindows)
        showsCalendarAgenda = defaults.bool(forKey: Key.showsCalendarAgenda)
        panelShortcuts = defaults.bool(forKey: Key.panelShortcuts)
        autoChecksForUpdates = defaults.bool(forKey: Key.autoChecksForUpdates)
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
    }
}
