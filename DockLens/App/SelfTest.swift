//
//  SelfTest.swift
//  DockLens
//
//  端到端自我測試（以 `--selftest` 啟動參數觸發，正常使用不會執行）。
//  App 自己合成滑鼠事件操作 Dock 與預覽面板，再從系統狀態（AX、視窗清單、前景 App）驗證結果：
//  1. 效能：依序 hover 每個執行中 App 的 Dock 圖示，量測「hover → 面板出現 → 縮圖就緒」延遲並截圖
//  2. 功能：對測試專用的 DockLensFixture（`--fixture <App 路徑>`）實際點擊面板上的每個按鈕。
//     關閉視窗、隱藏、結束等破壞性操作只對 Fixture 做，不碰使用者正在用的 App。
//  結果輸出到 ~/Library/Caches/com.firstfu.DockLens/selftest/（report.json + 面板截圖）。
//
//  另含 `--probe-label` 量測模式：暫停面板、讓游標停在圖示上，供外部截圖量測 Dock 名稱標籤位置
//  （PanelGeometry 的 Dock 版面常數即由此量得；macOS 改版時可重新量測）。
//

import AppKit
import EventKit
import ScreenCaptureKit
import ServiceManagement
import os

enum SelfTest {
    static let isRequested = CommandLine.arguments.contains("--selftest")

    /// 執行自我測試，完成後結束 App。
    static func run(coordinator: AppCoordinator) async {
        await SelfTestRunner(coordinator: coordinator).run()
    }

    /// 量測模式：暫停面板，讓游標停在前三個圖示上等放大動畫結束，與外部腳本以 /tmp/docklens-probe-* 檔案握手截圖。
    static func probeLabel(coordinator: AppCoordinator) async {
        let runner = SelfTestRunner(coordinator: coordinator)
        await runner.waitForServices()
        coordinator.preview.isSuspended = true
        var lines: [String] = []
        for (index, item) in runner.dockItems().prefix(3).enumerated() {
            guard let url = item.appURL else { continue }
            _ = await runner.hoverDock(appURL: url, expectPanelFor: nil, timeout: .zero)
            try? await Task.sleep(for: .milliseconds(1200))
            let settled = runner.dockItem(appURL: url)
            lines.append("\(index)\t\(item.title)\titem=\(settled.map { NSStringFromRect($0.frame) } ?? "nil")")
            FileManager.default.createFile(atPath: "/tmp/docklens-probe-ready-\(index)", contents: nil)
            for _ in 0..<60 where !FileManager.default.fileExists(atPath: "/tmp/docklens-probe-done-\(index)") {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/docklens-probe.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}

final class SelfTestRunner {
    struct Sample: Encodable {
        let app: String
        let windows: Int
        let showLatencyMs: Double?
        let thumbnailsReadyMs: Double?
        let thumbnailsLoaded: Int
        let screenshot: String?
    }

    struct Check: Encodable {
        let name: String
        let passed: Bool
        let detail: String
    }

    struct Report: Encodable {
        let date: Date
        let passed: Int
        let failed: Int
        let checks: [Check]
        let samples: [Sample]
        let hoverDelayMs: Double
        let loginItemStatus: String
        let peakMemoryMB: Double
    }

    private let coordinator: AppCoordinator
    private var preview: PreviewController { coordinator.preview }
    private let log = Logger(subsystem: "com.firstfu.DockLens", category: "selftest")
    private let output: URL
    private let primaryHeight: CGFloat
    private var samples: [Sample] = []
    private var checks: [Check] = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        output = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.firstfu.DockLens/selftest", directoryHint: .isDirectory)
        primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    }

    // MARK: - 主流程

    func run() async {
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await waitForServices()
        let originalMouse = NSEvent.mouseLocation
        let originalApp = NSWorkspace.shared.frontmostApplication

        // --calendar-only：只跑行程區塊檢查（約 10 秒；未授權時要等使用者按「允許」）
        if CommandLine.arguments.contains("--calendar-only") {
            await runCalendarChecks()
            writeReport()
            move(to: CGPoint(x: originalMouse.x, y: primaryHeight - originalMouse.y))
            NSApp.terminate(nil)
            return
        }
        // --media-only：只跑播放列檢查（除錯播放控制時用，約 20 秒）
        if CommandLine.arguments.contains("--media-only") {
            await runMediaChecks()
            writeReport()
            move(to: CGPoint(x: originalMouse.x, y: primaryHeight - originalMouse.y))
            NSApp.terminate(nil)
            return
        }
        // --recently-closed-app <App 路徑>：對「真的文件型 App」（例如 TextEdit）跑同一組檢查。
        // 只開、只關自己建立的測試文件（以檔案位置精確比對），不碰使用者原本開著的視窗，也不結束 App。
        if let index = CommandLine.arguments.firstIndex(of: "--recently-closed-app"), index + 1 < CommandLine.arguments.count {
            await runRecentlyClosedChecks(URL(fileURLWithPath: CommandLine.arguments[index + 1]), isFixture: false)
            writeReport()
            move(to: CGPoint(x: originalMouse.x, y: primaryHeight - originalMouse.y))
            if let originalApp, let window = WindowEnumerator.windows(for: originalApp.processIdentifier, includeOtherSpaces: false).first {
                WindowActions.focus(window)
            }
            NSApp.terminate(nil)
            return
        }
        // --recently-closed-soak <次數>：反覆開關 Fixture 的文件視窗，檢查偵測的紀錄不累積、記憶體不上漲（長時間使用的洩漏檢查）
        if let index = CommandLine.arguments.firstIndex(of: "--recently-closed-soak"), index + 1 < CommandLine.arguments.count,
           let fixtureIndex = CommandLine.arguments.firstIndex(of: "--fixture"), fixtureIndex + 1 < CommandLine.arguments.count {
            await runRecentlyClosedSoak(
                URL(fileURLWithPath: CommandLine.arguments[fixtureIndex + 1]), cycles: Int(CommandLine.arguments[index + 1]) ?? 100
            )
            writeReport()
            NSApp.terminate(nil)
            return
        }
        // --recently-closed-only：只跑「最近關閉」檢查（約 30 秒）
        if CommandLine.arguments.contains("--recently-closed-only"),
           let index = CommandLine.arguments.firstIndex(of: "--fixture"), index + 1 < CommandLine.arguments.count {
            await runRecentlyClosedChecks(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            writeReport()
            move(to: CGPoint(x: originalMouse.x, y: primaryHeight - originalMouse.y))
            NSApp.terminate(nil)
            return
        }
        await measureHoverLatency()
        await checkAutoHide()
        await runMediaChecks()
        await runCalendarChecks()
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), index + 1 < CommandLine.arguments.count {
            let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            await runFixtureChecks(fixtureURL)
            await runClosedWindowChecks(fixtureURL)
            await runRecentlyClosedChecks(fixtureURL)
        } else {
            record("功能測試", false, "未提供 --fixture，略過按鈕操作測試")
        }

        writeReport()
        // 還原：游標回原位、原本的前景 App 回到前景
        move(to: CGPoint(x: originalMouse.x, y: primaryHeight - originalMouse.y))
        if let originalApp, let window = WindowEnumerator.windows(for: originalApp.processIdentifier, includeOtherSpaces: false).first {
            WindowActions.focus(window)
        }
        try? await Task.sleep(for: .milliseconds(200))
        NSApp.terminate(nil)
    }

    func waitForServices() async {
        for _ in 0..<50 where !coordinator.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
    }

    // MARK: - 效能

    /// 依序 hover 前 8 個執行中 App，量測延遲；沒有視窗的 App 應該不彈出面板。
    private func measureHoverLatency() async {
        var checkedEmpty = false
        for item in dockItems().prefix(8) {
            guard let url = item.appURL, let app = runningApp(url) else { continue }
            let windowCount = WindowEnumerator.windows(
                for: app.processIdentifier, includeOtherSpaces: coordinator.settings.includesOtherSpaces
            ).count
            _ = await leaveDock()

            if windowCount == 0 {
                let shown = await hoverDock(appURL: url, expectPanelFor: app.processIdentifier, timeout: .milliseconds(700))
                if !checkedEmpty {
                    record("沒有視窗的 App 不彈出空面板", !shown, item.title)
                    checkedEmpty = true
                }
                continue
            }

            _ = await hoverDock(appURL: url, expectPanelFor: app.processIdentifier, timeout: .milliseconds(1500))
            // 無縮圖模式沒有「縮圖就緒」可等
            if ScreenRecordingAccess.isGranted {
                _ = await waitUntil(.seconds(1)) { self.preview.metrics?.readyAt != nil }
            }
            // 讓淡入動畫完成再截圖
            try? await Task.sleep(for: .milliseconds(200))
            let model = preview.currentModel
            let metrics = preview.metrics?.title == item.title ? preview.metrics : nil
            let sample = Sample(
                app: item.title,
                windows: model?.cards.count ?? 0,
                showLatencyMs: metrics?.presentedAt.map { milliseconds($0 - metrics!.hoverAt) },
                thumbnailsReadyMs: metrics?.readyAt.map { milliseconds($0 - metrics!.hoverAt) },
                thumbnailsLoaded: model?.cards.filter { $0.thumbnail != nil }.count ?? 0,
                screenshot: savePanelScreenshot("\(samples.count)-\(item.title)")
            )
            log.notice("\(sample.app, privacy: .public): 視窗 \(sample.windows)、顯示 \(sample.showLatencyMs ?? -1)ms、縮圖就緒 \(sample.thumbnailsReadyMs ?? -1)ms")
            samples.append(sample)
        }
    }

    /// 游標離開 Dock 與面板後，面板應自動收起。
    private func checkAutoHide() async {
        if !preview.isVisible, let item = dockItems().first(where: { item in
            item.appURL.flatMap(runningApp).map { !WindowEnumerator.windows(for: $0.processIdentifier, includeOtherSpaces: false).isEmpty } ?? false
        }), let url = item.appURL {
            _ = await hoverDock(appURL: url, expectPanelFor: nil, timeout: .seconds(1))
        }
        let wasVisible = preview.isVisible
        let hidden = await leaveDock()
        record("游標離開後面板自動收起", wasVisible && hidden, wasVisible ? "" : "前置條件：面板未顯示")
    }

    // MARK: - 播放列（Spotify／音樂）

    /// 對執行中的 Spotify 或音樂實際操作播放列，並盡量還原使用者的播放狀態。
    /// 尚未授權「自動化」時，按播放鈕會跳出系統詢問，需使用者按「允許」（程式無法代按），最多等 30 秒。
    private func runMediaChecks() async {
        guard let (item, app) = dockItems().lazy.compactMap({ item -> (DockItem, NSRunningApplication)? in
            guard let url = item.appURL, let app = self.runningApp(url), MediaPlayer(bundleID: app.bundleIdentifier) != nil else { return nil }
            return (item, app)
        }).first, let url = item.appURL else {
            record("音樂 App 顯示播放列", true, "略過：Dock 上沒有執行中的 Spotify 或音樂")
            return
        }
        let pid = app.processIdentifier
        _ = await leaveDock()
        let shown = await hoverDock(appURL: url, expectPanelFor: pid)
        func status() -> MediaStatus? { preview.currentModel?.media?.status }
        _ = await waitUntil(.seconds(2)) { status() != nil && status() != .loading }
        let barProbed = await waitUntil(.seconds(1)) { self.probeRect("media.playpause") != nil }
        let hasBar = shown && status() != nil && barProbed
        record("音樂 App 顯示播放列", hasBar, "\(item.title)：\(String(describing: status() ?? .loading))")
        guard hasBar else { return }

        if status() == .needsPermission {
            log.notice("等待使用者在系統詢問中允許控制 \(item.title, privacy: .public)")
            _ = await clickProbe("media.playpause")
            let decided = await waitUntil(.seconds(30)) {
                if case .track = status() { return true }
                return status() == .denied || status() == .stopped
            }
            record("按播放鈕觸發授權並讀到播放狀態", decided && status() != .denied, String(describing: status() ?? .loading))
        }
        guard case .track(let original) = status() else {
            record("播放／暫停切換", false, "前置條件：沒有歌曲（\(String(describing: status() ?? .loading))）")
            return
        }
        func current() -> NowPlaying? { if case .track(let track) = status() { return track } else { return nil } }

        // 播放／暫停：按兩次，狀態要先翻轉再回到原狀
        _ = await clickProbe("media.playpause")
        let flipped = await waitUntil(.seconds(2)) { current()?.isPlaying == !original.isPlaying }
        _ = await clickProbe("media.playpause")
        let restored = await waitUntil(.seconds(2)) { current()?.isPlaying == original.isPlaying }
        record("播放／暫停切換", flipped && restored, "原本\(original.isPlaying ? "播放中" : "暫停")、切換 \(flipped)、還原 \(restored)")

        // 下一首→上一首：歌名要先改變再回到原本那首。
        // 兩個會讓這項「看起來失敗」的外在狀況，不是 DockLens 的問題：
        // ① Spotify 免費帳號播廣告時不能切歌，「下一首」永遠不會生效 → 標示略過，不算失敗；
        // ② 目前這首播放超過 3 秒時，「上一首」是重播本首而不是回到前一首 → 沒回去就再按一次（第二次必定回前一首）
        _ = await clickProbe("media.next")
        let changed = await waitUntil(.seconds(2.5)) { (current()?.title).map { $0 != original.title } ?? false }
        guard changed else {
            record("下一首／上一首", true, "略過：播放器沒有切歌（多半是 Spotify 廣告不能略過）「\(original.title)」")
            _ = await leaveDock()
            return
        }
        _ = await clickProbe("media.previous")
        var back = await waitUntil(.seconds(2.5)) { current()?.title == original.title }
        if !back {
            _ = await clickProbe("media.previous")
            back = await waitUntil(.seconds(2.5)) { current()?.title == original.title }
        }
        record("下一首／上一首", back, "「\(original.title)」→ 換歌 \(changed)、回到原曲 \(back)")
        _ = await leaveDock()
    }

    // MARK: - 行程（行事曆）

    /// 游標停到「行事曆」Dock 圖示上（不論是否執行中），確認面板出現行程區塊並截圖。
    /// 尚未授權時按「允許」觸發系統詢問，需使用者回應（程式無法代按），最多等 3 分鐘：請求程序結束後才按「允許」會被系統丟棄。
    /// 不點行程列：那會打開行事曆 App、改變使用者的前景視窗。
    private func runCalendarChecks() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CalendarAgenda.calendarBundleID)?.standardizedFileURL,
              dockItem(appURL: url, includeStopped: true) != nil else {
            record("行事曆顯示行程", true, "略過：Dock 上沒有行事曆圖示")
            return
        }
        guard coordinator.settings.showsCalendarAgenda else {
            record("行事曆顯示行程", true, "略過：設定已關閉行程顯示")
            return
        }
        let running = runningApp(url) != nil
        _ = await leaveDock()
        _ = await hoverDock(appURL: url, expectPanelFor: nil)
        func status() -> AgendaStatus? { preview.currentModel?.agenda?.status }
        let shown = await waitUntil(.seconds(2)) { self.preview.isVisible && status() != nil }
        record("行事曆顯示行程", shown, "\(running ? "執行中" : "未執行")：\(String(describing: status()))")
        guard shown else { return }

        if status() == .needsPermission {
            log.notice("等待使用者在系統詢問中允許讀取行事曆")
            _ = await clickProbe("agenda.allow")
            // 使用者去按系統對話框時游標會離開面板、面板會收起，所以看系統授權狀態，回應後再重新滑過圖示
            let decided = await waitUntil(.seconds(180)) { EKEventStore.authorizationStatus(for: .event) != .notDetermined }
            _ = await leaveDock()
            _ = await hoverDock(appURL: url, expectPanelFor: nil)
            _ = await waitUntil(.seconds(2)) { status() != nil }
            let granted = status().map { $0 != .needsPermission && $0 != .denied } ?? false
            record("按「允許」觸發授權並讀到行程", decided && granted, String(describing: status()))
        }
        if case .day(let day) = status() {
            let rowsProbed = await waitUntil(.seconds(1)) { self.probeRect("agenda.row.\(day.events.count - 1)") != nil }
            let height = probeRect("agenda.row.0")?.height ?? 0
            record("行程列完整排版", rowsProbed && abs(height - AgendaView.rowHeight) < 1,
                   "\(day.kind == .today ? "今天" : "明天") \(day.events.count) 列（省略 \(day.hiddenCount)）、列高 \(height)")
        }
        // 等淡入動畫結束再截圖，否則會拍到半透明的空白面板
        try? await Task.sleep(for: .milliseconds(400))
        _ = savePanelScreenshot("calendar-agenda")
        _ = await leaveDock()
    }

    // MARK: - 功能（對 Fixture 實際點擊）

    private func runFixtureChecks(_ url: URL) async {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.firstfu.DockLensFixture"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.forceTerminate() }
        _ = await waitUntil(.seconds(2)) { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        guard let fixture = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else {
            record("啟動測試 App", false, url.path)
            return
        }
        let pid = fixture.processIdentifier
        defer { if !fixture.isTerminated { fixture.forceTerminate() } }
        guard await waitUntil(.seconds(5), { self.windowTitles(pid).count == 3 }),
              await waitUntil(.seconds(3), { self.dockItem(appURL: url) != nil }) else {
            record("啟動測試 App", false, "視窗 \(windowTitles(pid))、Dock 圖示 \(dockItem(appURL: url) != nil)")
            return
        }
        // 讓 Fixture 的視窗畫完
        try? await Task.sleep(for: .milliseconds(400))

        // 1. 顯示預覽
        var shown = await hoverDock(appURL: url, expectPanelFor: pid)
        let cardCount = preview.currentModel?.cards.count ?? 0
        if ScreenRecordingAccess.isGranted {
            let thumbnailsReady = await waitUntil(.seconds(1)) {
                self.preview.currentModel?.cards.allSatisfy { $0.thumbnail != nil } == true
            }
            record("預覽面板列出 3 個視窗且縮圖就緒", shown && cardCount == 3 && thumbnailsReady, "卡片 \(cardCount)")
        } else {
            // 無縮圖模式（--simulate-no-screen-recording）：卡片是圖示＋標題，標題必須從 AX 讀到
            let model = preview.currentModel
            let titles = model?.cards.map(\.window.title) ?? []
            let listMode = model?.showsThumbnails == false && model?.cards.allSatisfy { $0.thumbnail == nil } == true
            record("無縮圖模式：面板列出 3 個視窗與標題", shown && cardCount == 3 && listMode && !titles.contains(""),
                   "卡片 \(cardCount)、標題 \(titles)")
        }
        try? await Task.sleep(for: .milliseconds(200))
        _ = savePanelScreenshot("fixture")
        checkPanelPlacement(appTitle: "DockLensFixture")
        await saveContextScreenshot("context-\(DockPreferences.current.edge.rawValue)", icon: dockItem(appURL: url)?.frame)

        // 1b. Dock 重新啟動後（改 Dock 設定、killall Dock 都會觸發）應自動重新接上
        if CommandLine.arguments.contains("--restart-dock") {
            let oldDock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            _ = await leaveDock()
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
            let relaunched = await waitUntil(.seconds(8)) {
                let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
                return dock != nil && dock?.processIdentifier != oldDock && self.dockItem(appURL: url) != nil
            }
            // DockObserver 每 0.5 秒重試掛載
            try? await Task.sleep(for: .seconds(2))
            let reshown = relaunched ? await hoverDock(appURL: url, expectPanelFor: pid) : false
            record("Dock 重新啟動後自動接回", relaunched && reshown, "Dock 重啟 \(relaunched)、預覽 \(reshown)")
        }

        // 2. 移開後回到同一圖示
        _ = await leaveDock()
        shown = await hoverDock(appURL: url, expectPanelFor: pid)
        record("移開後回到同一圖示會再次顯示", shown)

        // 2b. 從圖示移往面板途中不收起；離開通道仍會收起
        await runTransitChecks(url: url, pid: pid)

        // 3. 滑過卡片浮現按鈕
        guard let second = window(pid, titled: "Fixture 2") else {
            record("滑過卡片浮現紅黃綠按鈕", false, "找不到 Fixture 2")
            return
        }
        await ensurePanel(url: url, pid: pid)
        let controlsShown = await hoverCard(second.id)
        record("滑過卡片浮現紅黃綠按鈕", controlsShown)

        // 4. 點縮圖切換視窗
        if let card = probeRect("card.\(second.id)") {
            await click(at: CGPoint(x: card.midX, y: card.midY))
        }
        let switched = await waitUntil(.seconds(2)) {
            !self.preview.isVisible && self.frontmostPID == pid && self.focusedWindowTitle(pid) == "Fixture 2"
        }
        record("點縮圖切換到該視窗", switched, "前景 \(frontmostPID == pid)、焦點「\(focusedWindowTitle(pid) ?? "nil")」")

        // 5. 點擊切換後，Dock 的選取狀態可能已過時，再次 hover 同一圖示仍應顯示
        shown = await hoverDock(appURL: url, expectPanelFor: pid)
        record("切換視窗後再次 hover 同一圖示會顯示", shown)

        // 6. 黃燈縮到 Dock
        if let third = window(pid, titled: "Fixture 3") {
            await ensurePanel(url: url, pid: pid)
            _ = await hoverCard(third.id)
            let clicked = await clickProbe("minimize.\(third.id)")
            let minimized = await waitUntil(.seconds(2)) { self.axWindow(pid, titled: "Fixture 3")?.isMinimized == true }
            let badge = await waitUntil(.seconds(1.5)) {
                self.preview.isVisible && self.preview.currentModel?.cards.first { $0.id == third.id }?.window.isMinimized == true
            }
            record("黃燈縮到 Dock，面板標示已縮小", clicked && minimized && badge, "點擊 \(clicked)、縮小 \(minimized)、標示 \(badge)")

            // 7. 再按黃燈還原（前一步必須真的縮小了，否則此項不成立）
            await ensurePanel(url: url, pid: pid)
            _ = await hoverCard(third.id)
            let wasMinimized = axWindow(pid, titled: "Fixture 3")?.isMinimized == true
            let clickedAgain = await clickProbe("minimize.\(third.id)")
            let restored = await waitUntil(.seconds(2)) { self.axWindow(pid, titled: "Fixture 3")?.isMinimized == false }
            record("再按黃燈還原視窗", wasMinimized && clickedAgain && restored, "原本已縮小 \(wasMinimized)")
            // 等面板就地更新完成（卡片不再標示已縮小）再進行下一步
            _ = await waitUntil(.seconds(1.5)) {
                self.preview.currentModel?.cards.first { $0.id == third.id }?.window.isMinimized == false
            }
            // 7b. 單鍵快捷鍵：游標在卡片上按 M 縮小、再按 M 還原（按鍵必須被面板吃掉，Fixture 不會收到）
            if AppSettings.shared.panelShortcuts {
                await ensurePanel(url: url, pid: pid)
                _ = await hoverCard(third.id)
                await pressKey(46) // M
                let keyMinimized = await waitUntil(.seconds(2)) { self.axWindow(pid, titled: "Fixture 3")?.isMinimized == true }
                let stillShown = await waitUntil(.seconds(1.5)) {
                    self.preview.isVisible && self.preview.currentModel?.cards.first { $0.id == third.id }?.window.isMinimized == true
                }
                _ = await hoverCard(third.id)
                await pressKey(46)
                let keyRestored = await waitUntil(.seconds(2)) { self.axWindow(pid, titled: "Fixture 3")?.isMinimized == false }
                record("游標在卡片上按 M 縮小、再按 M 還原", keyMinimized && stillShown && keyRestored,
                       "縮小 \(keyMinimized)、面板保留 \(stillShown)、還原 \(keyRestored)")
                _ = await waitUntil(.seconds(1.5)) {
                    self.preview.currentModel?.cards.first { $0.id == third.id }?.window.isMinimized == false
                }
            }
        } else {
            record("黃燈縮到 Dock，面板標示已縮小", false, "找不到 Fixture 3")
        }

        // 8. 紅燈關閉
        if let first = window(pid, titled: "Fixture 1") {
            await ensurePanel(url: url, pid: pid)
            let before = preview.currentModel?.cards.count ?? 0
            _ = await hoverCard(first.id)
            let clicked = await clickProbe("close.\(first.id)")
            let closed = await waitUntil(.seconds(2)) { !self.windowTitles(pid).contains("Fixture 1") }
            let updated = await waitUntil(.seconds(1.5)) {
                self.preview.isVisible && self.preview.currentModel?.cards.count == before - 1
            }
            record("紅燈關閉視窗，面板即時更新", clicked && closed && updated, "點擊 \(clicked)、關閉 \(closed)、更新 \(updated)")
        }

        // 9. ＋ 開新視窗
        await ensurePanel(url: url, pid: pid)
        let clickedNew = await clickProbe("header.new")
        let created = await waitUntil(.seconds(3)) { self.windowTitles(pid).contains("Fixture 4") }
        record("＋ 開新視窗", clickedNew && created, "前景 \(frontmostPID == pid)")

        // 10. 綠燈全螢幕（驗證後立即還原，避免留在全螢幕桌面）
        if let fourth = window(pid, titled: "Fixture 4") {
            await ensurePanel(url: url, pid: pid)
            _ = await hoverCard(fourth.id)
            let clicked = await clickProbe("fullscreen.\(fourth.id)")
            let fullScreen = await waitUntil(.seconds(4)) { self.isFullScreen(pid, titled: "Fixture 4") == true }
            record("綠燈切換全螢幕", clicked && fullScreen)
            if fullScreen, let element = axWindow(pid, titled: "Fixture 4") {
                element.set("AXFullScreen", kCFBooleanFalse)
                _ = await waitUntil(.seconds(4)) { self.isFullScreen(pid, titled: "Fixture 4") == false }
                try? await Task.sleep(for: .seconds(1))
            }
        } else {
            record("綠燈切換全螢幕", false, "找不到 Fixture 4")
        }

        // 11. 隱藏 App
        await ensurePanel(url: url, pid: pid)
        let clickedHide = await clickProbe("header.hide")
        let hidden = await waitUntil(.seconds(2)) { fixture.isHidden }
        record("隱藏 App", clickedHide && hidden)
        fixture.unhide()
        try? await Task.sleep(for: .milliseconds(600))

        // 11b. 游標在面板上按 H 隱藏 App
        if AppSettings.shared.panelShortcuts {
            await ensurePanel(url: url, pid: pid)
            if let card = preview.currentModel?.cards.first { _ = await hoverCard(card.id) }
            await pressKey(4) // H
            let keyHidden = await waitUntil(.seconds(2)) { fixture.isHidden }
            record("游標在面板上按 H 隱藏 App", keyHidden)
            fixture.unhide()
            try? await Task.sleep(for: .milliseconds(600))
        }

        // 12. 結束 App
        await ensurePanel(url: url, pid: pid)
        let clickedQuit = await clickProbe("header.quit")
        let quit = await waitUntil(.seconds(3)) { fixture.isTerminated }
        record("結束 App", clickedQuit && quit)
    }

    /// 模擬 Notion、Slack：按 X 只把主視窗藏起來的 App。面板應標示「已關閉」，點擊後由 App 重新打開視窗。
    private func runClosedWindowChecks(_ url: URL) async {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.firstfu.DockLensFixture"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.forceTerminate() }
        _ = await waitUntil(.seconds(2)) { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--hide-on-close"]
        guard let fixture = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else {
            record("啟動測試 App（按 X 只隱藏模式）", false)
            return
        }
        let pid = fixture.processIdentifier
        defer { if !fixture.isTerminated { fixture.forceTerminate() } }
        guard await waitUntil(.seconds(5), { self.windowTitles(pid) == ["Fixture Main"] }),
              await waitUntil(.seconds(3), { self.dockItem(appURL: url) != nil }),
              let main = window(pid, titled: "Fixture Main") else {
            record("啟動測試 App（按 X 只隱藏模式）", false, "視窗 \(windowTitles(pid))")
            return
        }
        try? await Task.sleep(for: .milliseconds(400))

        // 1. 用面板上的紅燈關掉唯一的視窗：App 只是把它藏起來，面板就地更新後應標示「已關閉」
        _ = await leaveDock()
        _ = await hoverDock(appURL: url, expectPanelFor: pid)
        _ = await hoverCard(main.id)
        let clicked = await clickProbe("close.\(main.id)")
        let hiddenByApp = await waitUntil(.seconds(2)) { !self.windowTitles(pid).contains("Fixture Main") }
        let marked = await waitUntil(.seconds(2)) {
            self.preview.isVisible && self.preview.currentModel?.cards.first?.window.isClosed == true
        }
        try? await Task.sleep(for: .milliseconds(200))
        _ = savePanelScreenshot("closed-window")
        record("按 X 關掉（App 仍保留）後面板標示已關閉", clicked && hiddenByApp && marked,
               "點擊 \(clicked)、已隱藏 \(hiddenByApp)、標示 \(marked)")

        // 2. 點已關閉的卡片：App 重新打開視窗
        var clickedCard = false
        if marked {
            _ = await waitUntil(.seconds(1)) { self.probeRect("card.\(main.id)") != nil }
            if let card = probeRect("card.\(main.id)") {
                await click(at: CGPoint(x: card.midX, y: card.midY))
                clickedCard = true
            }
        }
        let reopened = await waitUntil(.seconds(3)) { self.windowTitles(pid).contains("Fixture Main") }
        record("點已關閉的卡片會重新打開視窗", clickedCard && reopened, "前景 \(frontmostPID == pid)")

        fixture.terminate()
        _ = await waitUntil(.seconds(2)) { fixture.isTerminated }
    }

    // MARK: - 最近關閉（文件視窗）

    /// 模擬 TextEdit、預覽程式這類文件型 App：關掉文件視窗後，面板的「最近關閉」要列出它，點一下能重開。
    /// 涵蓋：偵測（真的經過 AXObserver）、面板就地出現、重開、全部關掉也能叫出面板、App 結束不算關視窗、設定開關。
    /// - Parameters:
    ///   - url: 測試 App 的位置
    ///   - isFixture: true 為 DockLensFixture（可任意啟動、結束）；false 為真實 App（不重啟、不結束，只動自己開的測試文件）
    private func runRecentlyClosedChecks(_ url: URL, isFixture: Bool = true) async {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.firstfu.DockLensFixture"
        let store = coordinator.closedWindows
        let label = isFixture ? "" : "（\(Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "真實 App")）"
        if isFixture {
            // 前面的測試關過沒有檔案的視窗（Fixture 1、2…）：它們不該出現在清單裡
            record("沒有檔案的視窗關掉不會進清單", store.entries(for: bundleID, limit: 10).isEmpty,
                   "筆數 \(store.entries(for: bundleID, limit: 10).count)")
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.forceTerminate() }
            _ = await waitUntil(.seconds(2)) { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
        }
        store.removeAll()

        // 兩份測試文件放在測試輸出資料夾（不碰使用者的任何檔案）
        let docs = output.appending(path: "docs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let fileA = docs.appending(path: "undo-A.txt"), fileB = docs.appending(path: "undo-B.txt")
        for file in [fileA, fileB] { try? "DockLens 最近關閉測試".write(to: file, atomically: true, encoding: .utf8) }

        // 要走真正的路徑：App 被切到前景 → DockLens 掛上監看 → 之後才關視窗
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let launched: NSRunningApplication?
        if isFixture {
            configuration.arguments = ["--document", fileA.path, "--document", fileB.path]
            launched = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            // 真實 App：用「開啟檔案」請它開兩份測試文件（App 已在執行就沿用，不重啟）
            _ = try? await NSWorkspace.shared.open([fileA, fileB], withApplicationAt: url, configuration: configuration)
            launched = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        guard let fixture = launched else {
            record("啟動測試 App（文件模式）\(label)", false)
            return
        }
        let pid = fixture.processIdentifier
        defer { if isFixture, !fixture.isTerminated { fixture.forceTerminate() } }
        // 真實 App 可能還開著使用者自己的文件：一律只看我們的兩份測試文件
        func documentWindows() -> [WindowInfo] { self.documentWindows(pid, matching: [fileA, fileB]) }
        func window(for file: URL) -> WindowInfo? {
            documentWindows().first { $0.documentURL.map(ClosedWindowPolicy.key) == ClosedWindowPolicy.key(file) }
        }
        guard await waitUntil(.seconds(5), { documentWindows().count == 2 }),
              await waitUntil(.seconds(3), { self.dockItem(appURL: url) != nil }),
              let windowB = window(for: fileB) else {
            record("啟動測試 App（文件模式）", false, "文件視窗 \(documentWindows().count)")
            return
        }
        record("視窗回報文件位置（AXDocument）\(label)", documentWindows().allSatisfy { ClosedWindowPolicy.isRestorable($0.documentURL) },
               documentWindows().compactMap { $0.documentURL?.lastPathComponent }.joined(separator: "、"))
        let attached = await waitUntil(.seconds(3)) { (self.coordinator.closedWatcher?.statistics(pid: pid).windows ?? 0) >= 2 }
        record("切到前景的 App 會被掛上監看\(label)", attached, "監看中 \(coordinator.closedWatcher?.statistics(pid: pid).windows ?? -1) 個視窗")
        try? await Task.sleep(for: .milliseconds(400))

        // 1. 用面板上的紅燈關掉 B：清單出現一筆，面板就地長出「最近關閉」
        _ = await leaveDock()
        _ = await hoverDock(appURL: url, expectPanelFor: pid)
        _ = await hoverCard(windowB.id)
        let clicked = await clickProbe("close.\(windowB.id)")
        let recorded = await waitUntil(.seconds(3)) { store.entries(for: bundleID).count == 1 }
        record("關掉文件視窗後進入最近關閉清單\(label)",
               clicked && recorded && store.entries(for: bundleID).first.map { ClosedWindowPolicy.key($0.url) == ClosedWindowPolicy.key(fileB) } == true,
               "點擊 \(clicked)、筆數 \(store.entries(for: bundleID).count)")
        let shown = await waitUntil(.seconds(3)) { self.preview.isVisible && self.preview.currentModel?.closed.count == 1 }
        _ = await waitUntil(.seconds(1)) { self.probeRect("closed.0") != nil }
        try? await Task.sleep(for: .milliseconds(200))
        _ = savePanelScreenshot("recently-closed")
        record("開著的面板就地出現「最近關閉」\(label)", shown && probeRect("closed.0") != nil, "面板 \(preview.isVisible)")

        // 2. 點那一筆：App 用同一個檔案重開視窗，清單拿掉這筆
        let clickedRow = await clickProbe("closed.0")
        let reopened = await waitUntil(.seconds(4)) { window(for: fileB) != nil }
        let removed = await waitUntil(.seconds(2)) { store.entries(for: bundleID).isEmpty }
        record("點最近關閉的項目會用原檔案重開視窗\(label)", clickedRow && reopened && removed,
               "點擊 \(clickedRow)、重開 \(reopened)、移除 \(removed)")

        // 3. 現在已經開著的文件不會再列出來（例如使用者自己用 ⌘O 重開）
        store.add(ClosedWindowEntry(bundleID: bundleID, title: "undo-B.txt", url: fileB))
        let hiddenWhenOpen = store.entries(for: bundleID, excludingOpen: [ClosedWindowPolicy.key(fileB)]).isEmpty
        store.removeAll()
        record("文件已經又開著時不列在最近關閉", hiddenWhenOpen)

        // 4. 兩個文件都關掉：App 沒有任何視窗，面板仍要能叫出來，列出兩筆（新的在前）
        for file in [fileA, fileB] {
            if let w = window(for: file) { WindowActions.close(w) }
        }
        let bothRecorded = await waitUntil(.seconds(4)) { store.entries(for: bundleID).count == 2 }
        record("連關兩個文件視窗都記得住\(label)", bothRecorded, "筆數 \(store.entries(for: bundleID).count)")
        _ = await leaveDock()
        let panelNoWindows = await hoverDock(appURL: url, expectPanelFor: pid)
        _ = await waitUntil(.seconds(1)) { self.probeRect("closed.1") != nil }
        _ = savePanelScreenshot("recently-closed-no-windows")
        record("App 沒有視窗時仍叫得出面板並列出最近關閉\(label)",
               // Fixture 的視窗物件關掉後還活一小段時間，會以「已關閉」卡片（點了重開 App）留在面板上；
               // 真正要驗的是：沒有任何「開著」的視窗時面板照樣叫得出來、最近關閉有兩筆
               // （真實 App 可能還有使用者自己開著的視窗，這項只在 Fixture 檢查）
               panelNoWindows && (!isFixture || preview.currentModel?.cards.allSatisfy(\.window.isClosed) == true)
                   && preview.currentModel?.closed.count == 2,
               "面板 \(panelNoWindows)、卡片 \(preview.currentModel?.cards.map(\.window.title) ?? [])、最近關閉 \(preview.currentModel?.closed.count ?? -1)")
        let clickedFirst = await clickProbe("closed.0")
        let restoredOne = await waitUntil(.seconds(4)) { documentWindows().count == 1 }
        record("全部關掉後也能從面板重開\(label)", clickedFirst && restoredOne, "文件視窗 \(documentWindows().count)")

        if isFixture {
            // 5. App 結束時視窗會一起被銷毀，不算使用者關掉視窗
            store.removeAll()
            fixture.terminate()
            _ = await waitUntil(.seconds(3)) { fixture.isTerminated }
            try? await Task.sleep(for: .milliseconds(1500))
            record("結束 App 不會把它的視窗當成關閉", store.entries(for: bundleID, limit: 10).isEmpty,
                   "筆數 \(store.entries(for: bundleID, limit: 10).count)")
        } else {
            // 真實 App：收尾，只關掉自己開的測試文件（以檔案位置精確比對），其餘視窗一概不動
            for file in [fileA, fileB] {
                if let w = window(for: file) { WindowActions.close(w) }
            }
            _ = await waitUntil(.seconds(3)) { self.documentWindows(pid, matching: [fileA, fileB]).isEmpty }
            store.removeAll()
        }

        // 6. 設定關閉：停止偵測並清空清單，不留任何檔案路徑；重新開啟後恢復
        store.add(ClosedWindowEntry(bundleID: bundleID, title: "x", url: fileA))
        let original = coordinator.settings.remembersClosedWindows
        coordinator.settings.remembersClosedWindows = false
        coordinator.applyClosedWindowSetting()
        let cleared = store.entries.isEmpty && coordinator.closedWatcher == nil
        coordinator.settings.remembersClosedWindows = true
        coordinator.applyClosedWindowSetting()
        record("關閉設定會停止偵測並清空清單", cleared && coordinator.closedWatcher != nil)
        coordinator.settings.remembersClosedWindows = original
        coordinator.applyClosedWindowSetting()
        try? FileManager.default.removeItem(at: docs)
    }

    /// 洩漏檢查：反覆「開檔案 → 視窗出現 → 關掉」N 次。每次都換新檔名，所以清單會一路填滿再擠掉舊的（容量 40）。
    /// 期望：偵測的 records 回到基準（視窗銷毀後不殘留）、清單不超過容量、DockLens 的實體記憶體不隨次數成長。
    private func runRecentlyClosedSoak(_ url: URL, cycles: Int) async {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.firstfu.DockLensFixture"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.forceTerminate() }
        _ = await waitUntil(.seconds(2)) { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
        let store = coordinator.closedWindows
        store.removeAll()
        let docs = output.appending(path: "soak", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let first = docs.appending(path: "soak-first.txt")
        try? "soak".write(to: first, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["--document", first.path]
        guard let fixture = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else {
            record("洩漏檢查：啟動測試 App", false)
            return
        }
        let pid = fixture.processIdentifier
        defer { if !fixture.isTerminated { fixture.forceTerminate() } }
        _ = await waitUntil(.seconds(5)) { (self.coordinator.closedWatcher?.statistics(pid: pid).windows ?? 0) >= 1 }
        let baseline = coordinator.closedWatcher?.statistics(pid: pid).windows ?? -1
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = false
        var failures = 0
        var footprints: [Double] = []
        for index in 0..<cycles {
            let file = docs.appending(path: "soak-\(index).txt")
            try? "soak \(index)".write(to: file, atomically: true, encoding: .utf8)
            _ = try? await NSWorkspace.shared.open([file], withApplicationAt: url, configuration: openConfiguration)
            let key = ClosedWindowPolicy.key(file)
            func target() -> WindowInfo? {
                WindowEnumerator.windows(for: pid, includeOtherSpaces: false)
                    .first { $0.documentURL.map(ClosedWindowPolicy.key) == key }
            }
            guard await waitUntil(.seconds(3), { target() != nil }), let window = target() else { failures += 1; continue }
            WindowActions.close(window)
            if !(await waitUntil(.seconds(3)) { target() == nil }) { failures += 1 }
            try? FileManager.default.removeItem(at: file)
            if index % max(1, cycles / 5) == 0 { footprints.append(physicalFootprintMB()) }
        }
        // 使用者之後再切到這個 App、或把游標停到它的 Dock 圖示時，偵測會重讀視窗並修剪已失效的紀錄；
        // 這裡走同一條路（面板顯示時會呼叫它），等視窗物件被系統真正釋放（Fixture 關掉的視窗還會活一小段時間）
        let fixtureBundleID = bundleID
        _ = await waitUntil(.seconds(8)) {
            self.coordinator.closedWatcher?.attach(pid: pid, bundleID: fixtureBundleID)
            return (self.coordinator.closedWatcher?.statistics(pid: pid).windows ?? -1) == baseline
        }
        footprints.append(physicalFootprintMB())
        let after = coordinator.closedWatcher?.statistics(pid: pid).windows ?? -1
        record("洩漏檢查：\(cycles) 次開關後偵測紀錄回到基準", after == baseline && failures == 0,
               "基準 \(baseline)、結束 \(after)、失敗 \(failures)、實際還開著 \(WindowEnumerator.windows(for: pid, includeOtherSpaces: false).map(\.title))、App 的 AX 視窗總數（含已關但未釋放的）\(rawWindowCount(pid))、紀錄 \(coordinator.closedWatcher?.recordSummaries(pid: pid) ?? [])")
        record("洩漏檢查：清單不超過容量", store.entries.count <= ClosedWindowStore.capacity,
               "筆數 \(store.entries.count)／\(ClosedWindowStore.capacity)")
        let growth = (footprints.last ?? 0) - (footprints.first ?? 0)
        record("洩漏檢查：實體記憶體沒有隨次數成長", growth < 8,
               "MB 走勢 \(footprints.map { String(format: "%.1f", $0) }.joined(separator: " → "))（增加 \(String(format: "%.1f", growth))）")
        try? FileManager.default.removeItem(at: docs)
    }

    /// App 回報的 AX 視窗總數（含已關閉但物件還沒被釋放的）。
    private func rawWindowCount(_ pid: pid_t) -> Int {
        let windows: [AXUIElement] = AXUIElementCreateApplication(pid).value(kAXWindowsAttribute) ?? []
        return windows.filter { $0.subrole == kAXStandardWindowSubrole as String }.count
    }

    /// DockLens 目前的實體記憶體用量（MB）。
    private func physicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// 面板應位於「放大圖示＋名稱標籤」之外，不蓋住 Dock。
    /// 底部 Dock 的標籤高度是實測常數；側邊 Dock 的標籤寬度隨 App 名稱而變，這裡檢查不蓋住放大圖示，標籤另以全景截圖目視確認。
    private func checkPanelPlacement(appTitle: String) {
        let prefs = DockPreferences.current
        guard let panel = preview.panelFrame else { return }
        let screens = NSScreen.screens
        guard let index = PanelGeometry.nearestScreen(to: CGPoint(x: panel.midX, y: panel.midY), in: screens.map(\.frame)) else { return }
        let screen = screens[index].frame
        switch prefs.edge {
        case .bottom:
            let floor = screen.minY + prefs.hoveredItemExtent + PanelGeometry.dockLabelHeight
            record("面板位於 Dock 名稱標籤上方", panel.minY >= floor,
                   String(format: "面板底距螢幕底 %.0f pt，Dock＋標籤頂 %.0f pt", panel.minY - screen.minY, floor - screen.minY))
        case .left:
            let floor = screen.minX + prefs.hoveredItemExtent
            record("面板位於 Dock 右側、不蓋住圖示", panel.minX >= floor,
                   String(format: "面板左緣距螢幕左 %.0f pt，放大圖示外緣 %.0f pt", panel.minX - screen.minX, floor - screen.minX))
        case .right:
            let ceiling = screen.maxX - prefs.hoveredItemExtent
            record("面板位於 Dock 左側、不蓋住圖示", panel.maxX <= ceiling,
                   String(format: "面板右緣距螢幕右 %.0f pt，放大圖示外緣 %.0f pt", screen.maxX - panel.maxX, screen.maxX - ceiling))
        }
    }

    /// 擷取「Dock 圖示＋名稱標籤＋面板」的全景畫面，供目視確認位置關係。
    private func saveContextScreenshot(_ name: String, icon axFrame: CGRect?) async {
        guard let panel = preview.panelFrame else { return }
        var rect = CGRect(x: panel.minX, y: primaryHeight - panel.maxY, width: panel.width, height: panel.height)
        if let axFrame { rect = rect.union(axFrame) }
        rect = rect.insetBy(dx: -40, dy: -40)
        guard let image = try? await SCScreenshotManager.captureImage(in: rect) else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: output.appending(path: "\(name).png"))
    }

    // MARK: - 面板操作

    /// 確保面板顯示的是指定 App；沒有的話重新 hover 它的 Dock 圖示。
    private func ensurePanel(url: URL, pid: pid_t) async {
        if preview.isVisible && preview.currentModel?.app?.processIdentifier == pid { return }
        _ = await hoverDock(appURL: url, expectPanelFor: pid)
    }

    /// 游標移到卡片上，等紅黃綠按鈕出現。先移到卡片外再移入，確保觸發 hover。
    private func hoverCard(_ windowID: CGWindowID) async -> Bool {
        _ = await waitUntil(.seconds(1)) { self.probeRect("card.\(windowID)") != nil }
        guard let card = probeRect("card.\(windowID)") else {
            log.error("找不到卡片位置：\(windowID)")
            return false
        }
        // 像真人一樣分段移入卡片
        for step in 0...4 {
            let y = card.minY - 9 + (card.midY - card.minY + 9) * CGFloat(step) / 4
            move(to: CGPoint(x: card.midX, y: y))
            try? await Task.sleep(for: .milliseconds(16))
        }
        let shown = await waitUntil(.milliseconds(800)) { UITestProbe.frame("close.\(windowID)") != nil }
        if !shown {
            let panel = preview.panelFrame.map { NSStringFromRect($0) } ?? "nil"
            let cards = preview.currentModel?.cards.map { "\($0.id):\(NSStringFromRect(UITestProbe.frame("card.\($0.id)") ?? .zero))" } ?? []
            log.error("卡片 \(windowID) 滑過後沒有出現按鈕；卡片 \(NSStringFromRect(card), privacy: .public)、面板 \(panel, privacy: .public)、游標 \(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)、所有卡片 \(cards.joined(separator: " "), privacy: .public)")
            _ = savePanelScreenshot("hover-fail-\(windowID)")
        }
        return shown
    }

    /// 點擊探針回報位置的元件中心。
    private func clickProbe(_ key: String) async -> Bool {
        // 面板剛換內容時，元件位置要等排版完成才會回報
        _ = await waitUntil(.seconds(1)) { self.probeRect(key) != nil }
        guard let rect = probeRect(key) else {
            log.error("找不到元件位置：\(key, privacy: .public)")
            return false
        }
        await click(at: CGPoint(x: rect.midX, y: rect.midY))
        return true
    }

    /// 探針座標（面板內容、左上原點）→ 全域 AX 座標（主螢幕左上原點）。
    private func probeRect(_ key: String) -> CGRect? {
        guard let rect = UITestProbe.frame(key), let panel = preview.panelFrame else { return nil }
        return CGRect(x: panel.minX + rect.minX, y: primaryHeight - panel.maxY + rect.minY, width: rect.width, height: rect.height)
    }

    private func savePanelScreenshot(_ name: String) -> String? {
        guard let windowID = preview.panelWindowID, let image = SkyLight.captureWindow(windowID) else { return nil }
        let file = "\(name).png"
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: output.appending(path: file))
        return file
    }

    // MARK: - Dock 操作

    /// Dock 上所有執行中 App 的圖示（AX 座標）。
    /// - Parameter includeStopped: 是否包含釘在 Dock 上但未執行的 App
    func dockItems(includeStopped: Bool = false) -> [DockItem] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let list = AXUIElementCreateApplication(dock.processIdentifier).children
                .first(where: { $0.role == kAXListRole as String }) else { return [] }
        return list.children.compactMap { element in
            guard element.subrole == "AXApplicationDockItem",
                  includeStopped || (element.value("AXIsApplicationRunning") as Bool?) == true,
                  let frame = element.frame else { return nil }
            let url: URL? = element.value(kAXURLAttribute)
            return DockItem(title: element.title ?? "", appURL: url?.standardizedFileURL, frame: frame)
        }
    }

    func dockItem(appURL: URL, includeStopped: Bool = false) -> DockItem? {
        let path = appURL.resolvingSymlinksInPath().path
        return dockItems(includeStopped: includeStopped).first { $0.appURL?.resolvingSymlinksInPath().path == path }
    }

    /// 游標從圖示移往面板途中的三種情境（對應「面板在半路突然消失」的回報）：
    /// 1. 慢慢往上移：途中超過寬限期也不能收起（回歸檢查；實測 Dock 此時不發取消選取）
    /// 2. 途中擦過沒有預覽的圖示（未執行或沒有視窗）：開放大效果時常發生，不能收起——回報的真正成因
    /// 3. 離開圖示列後沿螢幕邊走遠：仍要收起（Dock 不發取消選取，不能因此卡住不收）
    private func runTransitChecks(url: URL, pid: pid_t) async {
        // 1. 慢速往上：約 0.8 秒、20 步，遠超過 250ms 寬限期
        await ensurePanel(url: url, pid: pid)
        if let icon = dockItem(appURL: url)?.frame, let panel = preview.panelFrame {
            let start = CGPoint(x: icon.midX, y: icon.midY)
            let end = CGPoint(x: panel.midX, y: primaryHeight - panel.midY)
            var vanishedAt: Int?
            for step in 1...20 {
                let t = CGFloat(step) / 20
                move(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                try? await Task.sleep(for: .milliseconds(40))
                if vanishedAt == nil && !preview.isVisible { vanishedAt = step }
            }
            try? await Task.sleep(for: .milliseconds(400))
            let stayed = vanishedAt == nil && preview.isVisible && preview.currentModel?.app?.processIdentifier == pid
            record("慢慢從圖示移往面板，途中面板不消失", stayed, vanishedAt.map { "第 \($0)/20 步消失" } ?? "")
        } else {
            record("慢慢從圖示移往面板，途中面板不消失", false, "前置條件：面板未顯示")
        }

        // 2. 擦過沒有預覽的圖示後進入面板。
        //    直接送出 Dock 事件重現：放大效果下合成游標很難準確停在鄰居圖示上（曾落在空隙、測試無效）。
        //    全程每 10ms 取樣：舊行為會先收起、再被真正的 Dock 事件叫回來，只看最後狀態會誤判為通過。
        _ = await leaveDock()
        await ensurePanel(url: url, pid: pid)
        let unpreviewable = dockItems().first { item in
            guard item.appURL != url else { return false }
            guard let app = item.appURL.flatMap(runningApp) else { return true }
            return WindowEnumerator.windows(for: app.processIdentifier, includeOtherSpaces: coordinator.settings.includesOtherSpaces).isEmpty
        }
        if let target = unpreviewable, let icon = dockItem(appURL: url)?.frame, let panel = preview.panelFrame {
            // 游標先離開圖示往上（仍在 Dock 帶狀區內，事件才不會被當成過時而忽略）
            move(to: CGPoint(x: icon.midX, y: icon.minY - 6))
            try? await Task.sleep(for: .milliseconds(30))
            preview.dockHoverChanged(target)
            var vanished = false
            for tick in 0..<55 {
                if tick == 6 { move(to: CGPoint(x: panel.midX, y: primaryHeight - panel.midY)) }
                try? await Task.sleep(for: .milliseconds(10))
                if !preview.isVisible || preview.currentModel?.app?.processIdentifier != pid { vanished = true }
            }
            record("途中擦過沒有預覽的圖示，面板不消失", !vanished, "擦過「\(target.title)」")
        } else {
            record("途中擦過沒有預覽的圖示，面板不消失", true, "略過：Dock 上沒有未執行或沒有視窗的 App")
        }

        // 3. 進入通道後沿螢幕邊走遠（離開圖示列、仍在 Dock 帶狀區）：仍要收起
        _ = await leaveDock()
        await ensurePanel(url: url, pid: pid)
        if let icon = dockItem(appURL: url)?.frame, let panel = preview.panelFrame {
            let edge = DockPreferences.current.edge
            let screen = dockScreen(near: icon)
            let corridorPoint: CGPoint
            let farPoint: CGPoint
            switch edge {
            case .bottom:
                let y = primaryHeight - (panel.minY - 10)
                corridorPoint = CGPoint(x: icon.midX, y: y)
                farPoint = CGPoint(x: icon.midX < screen.midX ? screen.maxX - 20 : screen.minX + 20, y: y)
            case .left, .right:
                let x = edge == .left ? panel.minX - 10 : panel.maxX + 10
                corridorPoint = CGPoint(x: x, y: icon.midY)
                let farY = icon.midY < primaryHeight - screen.midY ? primaryHeight - screen.minY - 20 : primaryHeight - screen.maxY + 20
                farPoint = CGPoint(x: x, y: farY)
            }
            move(to: corridorPoint)
            try? await Task.sleep(for: .milliseconds(400))
            let heldInCorridor = preview.isVisible
            move(to: farPoint)
            let hidden = await waitUntil(.seconds(1.5)) { !self.preview.isVisible }
            record("游標停在通道時保留、往旁邊走開後收起", heldInCorridor && hidden, "通道內保留 \(heldInCorridor)、走開後收起 \(hidden)")
        } else {
            record("游標停在通道時保留、往旁邊走開後收起", false, "前置條件：面板未顯示")
        }
        _ = await leaveDock()
    }

    /// 讓游標停到指定 App 的 Dock 圖示上：先碰螢幕底邊讓自動隱藏的 Dock 滑出，再逐步校正到圖示中心
    /// （Dock 放大效果會讓圖示位置隨游標漂移），直到 Dock 回報選中它。
    /// - Parameters:
    ///   - expectPanelFor: 期待面板顯示此 pid 的內容；nil 表示只要面板出現即可
    ///   - timeout: 等面板出現的時間；`.zero` 表示不等
    /// - Returns: 面板是否在時限內顯示
    func hoverDock(appURL: URL, expectPanelFor pid: pid_t?, timeout: Duration = .milliseconds(1500)) async -> Bool {
        guard let first = dockItem(appURL: appURL, includeStopped: true) else { return false }
        let edge = DockPreferences.current.edge
        // 沿 Dock 方向的座標（底部 Dock 為 x、側邊為 y）固定用「放大前」的圖示中心：Dock 放大以游標為中心，
        // 游標停在這裡時底下的圖示不會漂移；若改追放大後的即時位置，會在相鄰圖示間來回跳。
        var along = edge == .bottom ? first.frame.midX : first.frame.midY
        move(to: edgePoint(along: along, near: first.frame, edge: edge))
        try? await Task.sleep(for: .milliseconds(500))
        for _ in 0..<12 {
            guard let item = dockItem(appURL: appURL, includeStopped: true) else { return false }
            let across = edge == .bottom ? item.frame.midY : item.frame.midX
            move(to: edge == .bottom ? CGPoint(x: along, y: across) : CGPoint(x: across, y: along))
            try? await Task.sleep(for: .milliseconds(60))
            let selected = coordinator.currentDockItem()
            if selected?.title == item.title { break }
            // 自動隱藏的 Dock 收起後，AX 回報的圖示位置可能停留在上次放大時的樣子，第一次常落在鄰居圖示上。
            // 依 Dock 實際選中的圖示與目標的相對位置修正，每次只移一半（阻尼），避免被放大效果帶著來回跳。
            func position(_ frame: CGRect) -> CGFloat { edge == .bottom ? frame.midX : frame.midY }
            let target = dockItem(appURL: appURL, includeStopped: true).map { position($0.frame) } ?? along
            along += (target - (selected.map { position($0.frame) } ?? along)) * 0.5
        }
        guard timeout > .zero else { return false }
        return await waitUntil(timeout) {
            self.preview.isVisible && (pid == nil || self.preview.currentModel?.app?.processIdentifier == pid)
        }
    }

    /// 游標移到 Dock 所在螢幕中央（遠離 Dock 與面板），等面板收起。
    /// - Returns: 面板是否已收起
    private func leaveDock() async -> Bool {
        let anchor = dockItems().first?.frame ?? .zero
        let screens = NSScreen.screens
        let center = CGPoint(x: anchor.midX, y: primaryHeight - anchor.midY)
        let screen = PanelGeometry.nearestScreen(to: center, in: screens.map(\.frame)).map { screens[$0].frame } ?? .zero
        move(to: CGPoint(x: screen.midX, y: primaryHeight - screen.midY))
        return await waitUntil(.seconds(1)) { !self.preview.isVisible }
    }

    /// Dock 所在螢幕邊緣上、沿 Dock 方向位於 `along` 的點（AX 座標，往內縮 1pt）；碰到它自動隱藏的 Dock 才會滑出。
    private func edgePoint(along: CGFloat, near frame: CGRect, edge: DockEdge) -> CGPoint {
        let screen = dockScreen(near: frame)
        switch edge {
        case .bottom: return CGPoint(x: along, y: primaryHeight - screen.minY - 1)
        case .left: return CGPoint(x: screen.minX + 1, y: along)
        case .right: return CGPoint(x: screen.maxX - 1, y: along)
        }
    }

    /// 圖示所在的螢幕（Cocoa 座標外框）。
    private func dockScreen(near axFrame: CGRect) -> CGRect {
        let screens = NSScreen.screens
        let center = CGPoint(x: axFrame.midX, y: primaryHeight - axFrame.midY)
        return PanelGeometry.nearestScreen(to: center, in: screens.map(\.frame)).map { screens[$0].frame } ?? .zero
    }

    // MARK: - 合成滑鼠事件（AX 座標）

    private func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func click(at point: CGPoint) async {
        move(to: point)
        try? await Task.sleep(for: .milliseconds(50))
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(30))
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// 模擬按下並放開一個鍵（不帶修飾鍵）。
    /// - Parameter keyCode: 實體鍵碼（ANSI 配置：M = 46、H = 4）
    private func pressKey(_ keyCode: CGKeyCode) async {
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown)
            // 來源為 nil 時事件會帶上不相干的修飾鍵旗標（實測含 ⌘⇧），會被當成組合鍵放行，必須明確清空
            event?.flags = []
            event?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    // MARK: - 系統狀態查詢

    private var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    private func runningApp(_ url: URL) -> NSRunningApplication? {
        let path = url.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.resolvingSymlinksInPath().path == path }
    }

    private func windowTitles(_ pid: pid_t) -> [String] {
        WindowEnumerator.windows(for: pid, includeOtherSpaces: false).map(\.title)
    }

    /// App 目前開著、且文件位置屬於 `files` 的視窗。
    private func documentWindows(_ pid: pid_t, matching files: [URL]) -> [WindowInfo] {
        let keys = Set(files.map(ClosedWindowPolicy.key))
        return WindowEnumerator.windows(for: pid, includeOtherSpaces: false)
            .filter { $0.documentURL.map { keys.contains(ClosedWindowPolicy.key($0)) } == true }
    }

    private func window(_ pid: pid_t, titled title: String) -> WindowInfo? {
        WindowEnumerator.windows(for: pid, includeOtherSpaces: false).first { $0.title == title }
    }

    private func axWindow(_ pid: pid_t, titled title: String) -> AXUIElement? {
        let windows: [AXUIElement] = AXUIElementCreateApplication(pid).value(kAXWindowsAttribute) ?? []
        return windows.first { $0.title == title }
    }

    private func focusedWindowTitle(_ pid: pid_t) -> String? {
        let focused: AXUIElement? = AXUIElementCreateApplication(pid).value(kAXFocusedWindowAttribute)
        return focused?.title
    }

    private func isFullScreen(_ pid: pid_t, titled title: String) -> Bool? {
        axWindow(pid, titled: title).flatMap { $0.value("AXFullScreen") as Bool? }
    }

    // MARK: - 紀錄

    private func record(_ name: String, _ passed: Bool, _ detail: String = "") {
        checks.append(Check(name: name, passed: passed, detail: detail))
        log.notice("\(passed ? "✅" : "❌", privacy: .public) \(name, privacy: .public) \(detail, privacy: .public)")
    }

    private func writeReport() {
        let status = switch SMAppService.mainApp.status {
        case .enabled: "enabled"
        case .notRegistered: "notRegistered"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
        let report = Report(
            date: .now,
            passed: checks.filter(\.passed).count,
            failed: checks.filter { !$0.passed }.count,
            checks: checks,
            samples: samples,
            hoverDelayMs: coordinator.settings.hoverDelay * 1000,
            loginItemStatus: status,
            peakMemoryMB: peakMemoryMB()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(report).write(to: output.appending(path: "report.json"))
    }

    // MARK: - 工具

    private func waitUntil(_ timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return ((Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15) * 10).rounded() / 10
    }

    private func peakMemoryMB() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        // macOS 的 ru_maxrss 單位為 bytes
        return (Double(usage.ru_maxrss) / 1_048_576 * 10).rounded() / 10
    }
}
