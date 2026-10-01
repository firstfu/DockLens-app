//
//  DockObserver.swift
//  DockLens
//
//  偵測游標目前停在 Dock 的哪個圖示上。
//  做法：對 Dock process 的 AXList 註冊 `AXSelectedChildrenChanged` 通知——游標移入/移出圖示時
//  Dock 自己會發出這個通知。完全事件驅動、零輪詢，閒置時 CPU 使用率為 0。
//  Dock 重新啟動（例如 `killall Dock`、改 Dock 設定）會讓 observer 失效，因此監聽 Dock process 結束並自動重掛。
//  注意：Dock 由 launchd 直接重啟，不會發出 NSWorkspace 的 App 啟動通知（實測），必須監聽 process 結束事件。
//

import AppKit
import ApplicationServices
import os

/// 游標停留的 Dock 圖示。
struct DockItem: Equatable {
    /// 圖示標題（App 名稱）
    let title: String
    /// App bundle 位置；用來對應到執行中的 App
    let appURL: URL?
    /// 圖示外框（AX 座標：主螢幕左上角為原點、Y 向下）
    let frame: CGRect
}

/// Dock 的外觀偏好（位置、圖示大小、放大效果）。從 com.apple.dock 偏好讀取（走 cfprefs 快取，成本極低）。
struct DockPreferences {
    let edge: DockEdge
    /// 圖示大小；偏好中沒有此值時為 nil
    let tileSize: CGFloat?
    /// 放大後的圖示大小
    let largeSize: CGFloat?
    let magnification: Bool

    static var current: DockPreferences {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        func size(_ key: String) -> CGFloat? {
            (defaults?.object(forKey: key) as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        return DockPreferences(
            edge: DockEdge(rawValue: defaults?.string(forKey: "orientation") ?? "bottom") ?? .bottom,
            tileSize: size("tilesize"),
            largeSize: size("largesize"),
            magnification: defaults?.bool(forKey: "magnification") ?? false
        )
    }

    /// 游標所在圖示「放大且靜止」時，距 Dock 所在螢幕邊的厚度；偏好不足以推算時為 0（改用即時圖示位置）。
    var hoveredItemExtent: CGFloat {
        guard let tileSize else { return 0 }
        return PanelGeometry.dockItemExtent(tileSize: tileSize, largeSize: largeSize ?? tileSize, magnification: magnification)
    }
}

final class DockObserver {
    /// 游標所在圖示改變時呼叫（移出所有 App 圖示時為 nil）
    var onHoverChange: ((DockItem?) -> Void)?

    private var observer: AXObserver?
    private var list: AXUIElement?
    private var dockPID: pid_t = 0
    private var launchObservation: NSObjectProtocol?
    /// 監聽 Dock process 結束（kqueue，閒置零成本）
    private var exitSource: DispatchSourceProcess?
    private let log = Logger(subsystem: "com.firstfu.DockLens", category: "dock")

    /// 開始監聽。需要輔助使用（Accessibility）權限。
    /// - Returns: 是否成功掛上 Dock（Dock 尚未就緒時會回傳 false，稍後可再呼叫）
    @discardableResult
    func start() -> Bool {
        if launchObservation == nil {
            launchObservation = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == "com.apple.dock" else { return }
                MainActor.assumeIsolated { self?.reattachAfterDockRestart() }
            }
        }
        return attach()
    }

    /// 停止監聽並釋放 observer。
    func stop() {
        detach()
        exitSource?.cancel()
        exitSource = nil
        if let launchObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObservation)
        }
        launchObservation = nil
    }

    // MARK: - 掛載

    @discardableResult
    private func attach() -> Bool {
        detach()
        // Dock 剛結束時清單可能還殘留舊的那個，只接仍在執行的
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated }) else {
            log.error("找不到 Dock process")
            return false
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = app.children.first(where: { $0.role == kAXListRole as String }) else {
            log.error("Dock AX 樹尚未就緒或沒有輔助使用權限")
            return false
        }

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            // run loop source 掛在主執行緒，callback 必定在主執行緒觸發
            MainActor.assumeIsolated {
                Unmanaged<DockObserver>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
            }
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &newObserver) == .success, let newObserver else {
            log.error("AXObserverCreate 失敗")
            return false
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(newObserver, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard result == .success else {
            log.error("註冊 Dock 通知失敗：\(result.rawValue)")
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        watchExit(of: dock.processIdentifier)

        observer = newObserver
        self.list = list
        dockPID = dock.processIdentifier
        log.info("已掛上 Dock（pid \(dock.processIdentifier)）")
        return true
    }

    /// Dock process 一結束就開始重掛，不等（也等不到）App 啟動通知。
    private func watchExit(of pid: pid_t) {
        exitSource?.cancel()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.log.notice("Dock 已結束，等待重新啟動後重掛")
                self?.reattachAfterDockRestart()
            }
        }
        source.resume()
        exitSource = source
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        list = nil
    }

    /// Dock 重啟後 AX 樹需要一點時間才建好，最多重試 20 次（每次間隔 0.5 秒）。
    private func reattachAfterDockRestart(attempt: Int = 0) {
        if attempt == 0 {
            detach()
            onHoverChange?(nil)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.observer == nil else { return }
            if !self.attach() && attempt < 20 {
                self.reattachAfterDockRestart(attempt: attempt + 1)
            }
        }
    }

    // MARK: - 事件

    private func selectionChanged() {
        onHoverChange?(currentItem())
    }

    /// 讀取目前被選取（游標停留）的 Dock 圖示；只回傳「App」類型圖示。
    /// 直接向 Dock 查詢（一次 AX IPC，<1ms），不依賴通知，可用來取得放大動畫後的即時位置。
    func currentItem() -> DockItem? {
        guard let list,
              let selected: [AXUIElement] = list.value(kAXSelectedChildrenAttribute),
              let element = selected.first,
              element.subrole == "AXApplicationDockItem",
              let frame = element.frame else { return nil }
        let url: URL? = element.value(kAXURLAttribute)
        return DockItem(title: element.title ?? "", appURL: url?.standardizedFileURL, frame: frame)
    }
}
