//
//  AppCoordinator.swift
//  DockLens
//
//  App 的組裝中心：持有各服務、處理權限就緒後的啟動流程、監聽系統 App 生命週期事件（預熱/清快取）。
//

import AppKit
import Observation
import SwiftUI

@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings = AppSettings.shared
    let permissions = Permissions()
    let updates = UpdateChecker(settings: AppSettings.shared)
    @ObservationIgnored let thumbnails = ThumbnailService()
    @ObservationIgnored private(set) lazy var preview = PreviewController(settings: settings, thumbnails: thumbnails)
    @ObservationIgnored private let dock = DockObserver()
    /// 最近關閉的文件視窗（只在記憶體）；`closedWatcher` 負責偵測，只在設定開啟時存在
    @ObservationIgnored let closedWindows = ClosedWindowStore()
    @ObservationIgnored private(set) var closedWatcher: ClosedWindowWatcher?
    @ObservationIgnored private var workspaceObservations: [NSObjectProtocol] = []
    @ObservationIgnored private var onboardingWindow: NSWindow?

    private(set) var isRunning = false

    private init() {}

    /// App 啟動時呼叫：有輔助使用就開始運作；缺權限時顯示引導視窗並輪詢。
    /// 螢幕錄製是選用的：沒有時以無縮圖模式運作，引導視窗只在使用者還沒表態過時出現。
    func launch() {
        #if DEBUG
        // 翻譯排版檢查只畫假資料，不啟動任何服務、不跳引導
        if UIRender.outputDirectory != nil { return }
        #endif
        updates.applyAutoCheckSetting()
        permissions.onAccessibilityGranted = { [weak self] in
            guard let self else { return }
            self.startServices()
            // 引導已被關掉（使用者自己去系統設定授權）：已能運作，不必為了選用的螢幕錄製繼續每秒輪詢
            if self.onboardingWindow?.isVisible != true { self.permissions.stopPolling() }
        }
        permissions.onAllGranted = { [weak self] in self?.onboardingWindow?.close() }
        if permissions.accessibility {
            startServices()
        }
        if Self.needsOnboarding(
            accessibility: permissions.accessibility,
            screenRecording: permissions.screenRecording,
            declinedScreenRecording: settings.declinedScreenRecording || SelfTest.isRequested
        ) {
            showOnboarding()
        }
    }

    /// 啟動時是否要顯示權限引導。
    /// - Parameters:
    ///   - accessibility: 是否已有輔助使用（必要權限）
    ///   - screenRecording: 是否已有螢幕錄製（選用權限）
    ///   - declinedScreenRecording: 使用者是否已選擇不給螢幕錄製（自我測試也視為已表態，避免引導擋住面板）
    /// - Returns: 缺必要權限，或缺選用權限且使用者還沒表態時為 true
    nonisolated static func needsOnboarding(accessibility: Bool, screenRecording: Bool, declinedScreenRecording: Bool) -> Bool {
        !accessibility || (!screenRecording && !declinedScreenRecording)
    }

    /// 使用者在引導中選擇「先不要縮圖」：記下選擇並關閉引導，之後啟動不再詢問。
    func continueWithoutScreenRecording() {
        settings.declinedScreenRecording = true
        onboardingWindow?.close()
    }

    /// 開始監聽 Dock 與系統事件。
    func startServices() {
        guard !isRunning else { return }
        dock.onHoverChange = { [weak self] item in self?.preview.dockHoverChanged(item) }
        preview.dockObserver = dock
        preview.closedWindows = closedWindows
        preview.refreshClosedWindowWatching = { [weak self] app in self?.watchClosedWindows(of: app) }
        guard dock.start() else {
            // Dock 尚未就緒（或權限剛授予、AX 樹還沒建立），稍後重試
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startServices()
            }
            return
        }
        observeWorkspace()
        applyClosedWindowSetting()
        isRunning = true
    }

    /// 依設定啟動或停止「最近關閉」的偵測；關閉時一併清空已記下的項目（不留任何使用者檔案路徑）。
    func applyClosedWindowSetting() {
        guard isRunning || permissions.accessibility else { return }
        if settings.remembersClosedWindows {
            guard closedWatcher == nil else { return }
            let store = closedWindows
            closedWatcher = ClosedWindowWatcher { [weak self] closed in
                MainActor.assumeIsolated {
                    // 回報在關閉後約半秒才到：這段時間內使用者可能已經把設定關掉，不能再留下檔案路徑
                    guard self?.settings.remembersClosedWindows == true, self?.closedWatcher != nil else { return }
                    store.add(ClosedWindowEntry(
                        bundleID: closed.bundleID, title: closed.title, url: closed.url, closedAt: closed.closedAt
                    ))
                }
            }
            // 已經在前景的 App 不會再收到「切到前景」通知，啟動時先掛上
            if let front = NSWorkspace.shared.frontmostApplication { watchClosedWindows(of: front) }
        } else {
            closedWatcher?.stop()
            closedWatcher = nil
            closedWindows.removeAll()
        }
    }

    /// 開始監看某個 App 的視窗關閉（只監看一般 App，不含 DockLens 自己）。
    private func watchClosedWindows(of app: NSRunningApplication) {
        guard let watcher = closedWatcher, app.activationPolicy == .regular, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier else { return }
        watcher.attach(pid: app.processIdentifier, bundleID: bundleID)
    }

    /// 直接向 Dock 查詢游標目前停在哪個 App 圖示上（不依賴通知；自我測試用）。
    func currentDockItem() -> DockItem? {
        dock.currentItem()
    }

    /// 顯示權限引導視窗並開始輪詢權限。agent App 沒有 Dock 圖示，需主動啟用才會浮到最前。
    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // 視窗高度跟著內容走：翻譯長度各語言差很多（德文、俄文比中文長一倍以上），
            // 授權後底部說明也會換掉，固定高度會截字或留白
            let controller = NSHostingController(rootView: OnboardingView(
                permissions: permissions,
                continueWithoutScreenRecording: { [weak self] in self?.continueWithoutScreenRecording() }
            ))
            controller.sizingOptions = [.preferredContentSize]
            window.contentViewController = controller
            window.center()
            // 關掉引導時：已能運作就停止輪詢（閒置不該每秒喚醒）；還缺輔助使用則繼續等，授權後自動開始
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.permissions.accessibility else { return }
                    self.permissions.stopPolling()
                }
            }
            onboardingWindow = window
        }
        permissions.refresh()
        // 從選單打開時權限可能已在系統設定裡補齊（選單顯示的狀態是舊的），不必再跳引導
        guard !permissions.allGranted else { return }
        permissions.startPolling()
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 系統事件

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        // App 失去焦點時預熱它的縮圖：稍後游標移到它的 Dock 圖示時，快取已是最新畫面
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                guard let self, pid != ProcessInfo.processInfo.processIdentifier else { return }
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let maxPixelWidth = Int(self.settings.thumbnailHeight * PanelGeometry.maxAspect * scale)
                self.thumbnails.prewarm(pid: pid, maxPixelWidth: maxPixelWidth)
            }
        })
        // 使用者切到某個 App：開始（或重新整理）監看它的視窗，之後關掉的文件才記得住
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.watchClosedWindows(of: app) }
        })
        // App 結束時釋放它的縮圖
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.thumbnails.purge(pid: pid)
                self?.closedWatcher?.detach(pid: pid)
                // 結束得慢的 App（要存檔、跳詢問）視窗是一個個被銷毀的，可能被誤當成「關掉的視窗」：把剛記下的清掉
                if let bundleID = app.bundleIdentifier { self?.closedWindows.removeRecent(bundleID: bundleID, within: 3) }
            }
        })
        // 切換桌面時收起面板
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preview.hide() }
        })
    }
}
