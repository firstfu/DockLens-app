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
    @ObservationIgnored let thumbnails = ThumbnailService()
    @ObservationIgnored private(set) lazy var preview = PreviewController(settings: settings, thumbnails: thumbnails)
    @ObservationIgnored private let dock = DockObserver()
    @ObservationIgnored private var workspaceObservations: [NSObjectProtocol] = []
    @ObservationIgnored private var onboardingWindow: NSWindow?

    private(set) var isRunning = false

    private init() {}

    /// App 啟動時呼叫：權限齊全就直接開始，否則顯示引導視窗並輪詢權限。
    func launch() {
        permissions.onAllGranted = { [weak self] in
            self?.startServices()
            self?.onboardingWindow?.close()
        }
        if permissions.allGranted {
            startServices()
        } else {
            showOnboarding()
            permissions.startPolling()
        }
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

    /// 顯示權限引導視窗。agent App 沒有 Dock 圖示，需主動啟用才會浮到最前。
    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(permissions: permissions))
            window.center()
            onboardingWindow = window
        }
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
