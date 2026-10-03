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
    @ObservationIgnored private var workspaceObservations: [NSObjectProtocol] = []
    @ObservationIgnored private var onboardingWindow: NSWindow?

    private(set) var isRunning = false

    private init() {}

    /// App 啟動時呼叫：有輔助使用就開始運作；缺權限時顯示引導視窗並輪詢。
    /// 螢幕錄製是選用的：沒有時以無縮圖模式運作，引導視窗只在使用者還沒表態過時出現。
    func launch() {
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
        guard dock.start() else {
            // Dock 尚未就緒（或權限剛授予、AX 樹還沒建立），稍後重試
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startServices()
            }
            return
        }
        observeWorkspace()
        isRunning = true
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
            window.contentView = NSHostingView(rootView: OnboardingView(
                permissions: permissions,
                continueWithoutScreenRecording: { [weak self] in self?.continueWithoutScreenRecording() }
            ))
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
        // App 結束時釋放它的縮圖
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.thumbnails.purge(pid: pid) }
        })
        // 切換桌面時收起面板
        workspaceObservations.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preview.hide() }
        })
    }
}
