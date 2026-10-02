//
//  PreviewController.swift
//  DockLens
//
//  串起「Dock 游標事件 → 列舉視窗 → 擷取縮圖 → 顯示/定位/隱藏面板」的流程。
//
//  延遲感的關鍵設計：
//  - 游標一停上圖示就立刻開始列舉視窗與擷取縮圖，與「懸停延遲」重疊進行；延遲結束時縮圖多半已拍好。
//  - 面板已顯示時，在圖示間移動不再等待延遲，直接切換內容。
//  - 游標從圖示移往面板途中會短暫離開圖示，用 0.25 秒寬限期避免面板閃退。
//

import AppKit
import EventKit
import SwiftUI
import os

final class PreviewController {
    private let settings: AppSettings
    private let thumbnails: ThumbnailService
    private let panel = PreviewPanel()
    private let hostingView = PanelHostingView(rootView: AnyView(EmptyView()))
    private let log = Logger(subsystem: "com.firstfu.DockLens", category: "preview")

    private var hoveredItem: DockItem?
    private var model: PreviewModel?
    private var currentPID: pid_t?
    private var anchorIcon: CGRect = .zero
    private var isMouseInPanel = false
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var moveMonitor: Any?
    /// 面板顯示行程期間才掛上的 EKEventStoreChanged 監聽
    private var calendarObserver: NSObjectProtocol?
    private var isHidePending = false
    /// Dock 所在的帶狀區域（Cocoa 座標）；游標在此區或面板內時不收起面板
    private var dockBand: CGRect = .zero
    /// 圖示外緣到面板之間的通道（Cocoa 座標）；游標在此區時不收起
    private var corridor: CGRect = .zero
    /// Dock 圖示列（Cocoa 座標）；只有游標在此區內時才信任 Dock 回報的選取狀態
    private var dockRow: CGRect = .zero
    /// 目前 Dock 游標所在圖示能否產生預覽（未執行或沒有視窗時為 false）。
    /// 面板顯示中擦過這類圖示時不立刻收起，但這種圖示也不算「游標仍在 Dock 上」的理由。
    private var isHoveredItemPreviewable = true

    /// 用來即時查詢游標所在圖示的位置（放大動畫後）
    weak var dockObserver: DockObserver?

    /// 游標離開圖示/面板後，面板保留多久才隱藏
    private let hideGrace: Duration = .milliseconds(250)

    init(settings: AppSettings, thumbnails: ThumbnailService) {
        self.settings = settings
        self.thumbnails = thumbnails
        hostingView.onMouseInside = { [weak self] inside in self?.mouseInPanelChanged(inside) }
        hostingView.onMouseInsideChanged = { [weak self] inside in self?.setHoverPolling(inside) }
        hostingView.onMouseMoved = { [weak self] point in self?.model?.setHoveredCard(at: point) }
        panel.contentView = hostingView
    }

    var isVisible: Bool { panel.isVisible }
    /// 目前顯示中的內容（自我測試用）
    var currentModel: PreviewModel? { model }
    /// 暫停顯示面板（量測 Dock 原生外觀時用，只影響記憶體中的狀態）
    var isSuspended = false
    /// 延遲量測（自我測試用）：hover 到某圖示 → 面板出現 → 縮圖全部就緒
    struct Metrics {
        let title: String
        let hoverAt: ContinuousClock.Instant
        var presentedAt: ContinuousClock.Instant?
        var readyAt: ContinuousClock.Instant?
    }
    private(set) var metrics: Metrics?
    /// 目前 Dock 游標所在圖示標題（自我測試用）
    var hoveredTitle: String? { hoveredItem?.title }
    /// 面板外框（Cocoa 座標；自我測試換算按鈕位置用）
    var panelFrame: CGRect? { panel.isVisible ? panel.frame : nil }
    /// 面板的 CGWindowID（自我測試截圖用）
    var panelWindowID: CGWindowID? { panel.isVisible ? CGWindowID(panel.windowNumber) : nil }

    // MARK: - Dock 事件

    /// DockObserver 回報游標所在圖示改變。
    func dockHoverChanged(_ item: DockItem?) {
        if isSuspended { hoveredItem = item; return }
        // 自動隱藏的 Dock 在游標離開時偶爾會補發過時的選取事件；游標明明不在 Dock 上就忽略
        if item != nil, panel.isVisible, !dockBand.contains(NSEvent.mouseLocation) {
            log.notice("忽略過時的 Dock 事件：\(item?.title ?? "", privacy: .public)")
            return
        }
        if let item, item.title != hoveredItem?.title {
            metrics = Metrics(title: item.title, hoverAt: .now)
        }
        hoveredItem = item
        isHoveredItemPreviewable = true
        log.notice("hover: \(item?.title ?? "nil", privacy: .public)")
        guard settings.isEnabled, let item else {
            scheduleHide()
            return
        }
        cancelPendingHide()

        guard let app = runningApp(for: item) else {
            // 「行事曆」沒開也能看行程：游標停上時直接顯示今天的行程
            if showsAgenda(for: item.appURL) {
                if panel.isVisible && model?.app == nil && model?.appURL == item.appURL {
                    showTask?.cancel()
                    return
                }
                let delay: Duration = panel.isVisible ? .zero : .milliseconds(Int(settings.hoverDelay * 1000))
                showTask?.cancel()
                showTask = Task { [weak self] in await self?.prepareAndShow(app: nil, item: item, delay: delay) }
                return
            }
            log.notice("找不到執行中的 App：\(item.appURL?.path ?? "nil", privacy: .public)")
            // 未執行的 App：沒有視窗可預覽
            showTask?.cancel()
            dismissForUnpreviewableItem()
            return
        }
        // 同一個 App 且面板已在顯示：保持不動（避免 Dock 放大效果造成的重複事件讓面板抖動）。
        // 途中擦過的其他圖示可能還在列舉，要一併取消，否則它稍後會把面板換掉或收起。
        if panel.isVisible && app.processIdentifier == currentPID {
            showTask?.cancel()
            return
        }

        let delay: Duration = panel.isVisible ? .zero : .milliseconds(Int(settings.hoverDelay * 1000))
        showTask?.cancel()
        showTask = Task { [weak self] in await self?.prepareAndShow(app: app, item: item, delay: delay) }
    }

    // MARK: - 顯示流程

    /// - Parameters:
    ///   - app: 目標 App；nil 表示未執行的「行事曆」（只顯示行程）
    ///   - previousOrder: 就地更新時沿用的卡片順序（視窗 ID）；nil 表示依最近使用排序
    private func prepareAndShow(app: NSRunningApplication?, item: DockItem, delay: Duration, previousOrder: [CGWindowID]? = nil) async {
        let start = ContinuousClock.now
        let appURL = app?.bundleURL ?? item.appURL
        // 行程與視窗列舉並行：EventKit 查詢是本機資料庫，通常幾毫秒內完成
        let agendaTask: Task<AgendaStatus, Never>? = showsAgenda(for: appURL)
            ? Task.detached(priority: .userInitiated) { CalendarAgenda.status() } : nil
        guard let app else {
            guard let agenda = await agendaTask?.value, !Task.isCancelled else { return }
            await presentAfterDelay(
                PreviewModel(app: nil, appURL: appURL, title: item.title, windows: [], agenda: agenda,
                             thumbnail: { _ in nil }, thumbnailHeight: settings.thumbnailHeight,
                             showsTitles: settings.showsTitles, edge: DockPreferences.current.edge,
                             screenSize: screen(near: item.frame).visibleFrame.size),
                item: item, start: start, delay: delay
            )
            return
        }
        let pid = app.processIdentifier
        let includeOtherSpaces = settings.includesOtherSpaces
        let includeClosed = settings.showsClosedWindows
        // 列舉在背景執行緒（AX IPC 遇到忙碌的 App 可能要數十毫秒）
        var windows = await Task.detached(priority: .userInitiated) {
            WindowEnumerator.windows(for: pid, includeOtherSpaces: includeOtherSpaces, includeClosed: includeClosed)
        }.value
        let agenda = await agendaTask?.value
        // 就地更新（剛關掉/縮小視窗）時若列到 0 個：AX 已看不到被關的視窗，但 WindowServer 可能還沒把它標為
        // 「不在畫面上」，這段空窗期裡按 X 只是藏起來的視窗會被漏掉。稍等再確認，最多兩次，才決定收起面板。
        if previousOrder != nil {
            for _ in 0..<2 where windows.isEmpty && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                windows = await Task.detached(priority: .userInitiated) {
                    WindowEnumerator.windows(for: pid, includeOtherSpaces: includeOtherSpaces, includeClosed: includeClosed)
                }.value
            }
        }
        if let previousOrder {
            windows = Self.keepingOrder(windows, previous: previousOrder)
        }
        // 最後一道防線：無標題、非縮小、非「已關閉」的視窗若拍不出畫面，就是 App 的隱形輔助視窗，
        // 留著只會顯示「未命名視窗」的空白卡片（列舉規則漏網時兜底）
        let probeWidth = Int(settings.thumbnailHeight * PanelGeometry.maxAspect * 2)
        if windows.contains(where: { $0.title.isEmpty && !$0.isMinimized && !$0.isClosed }) {
            let service = thumbnails
            let candidates = windows
            windows = await Task.detached(priority: .userInitiated) {
                candidates.filter { w in
                    !(w.title.isEmpty && !w.isMinimized && !w.isClosed) || service.canCapture(w, maxPixelWidth: probeWidth)
                }
            }.value
        }
        guard !Task.isCancelled else { return }
        log.notice("列舉 \(app.localizedName ?? "", privacy: .public)：\(windows.count) 個視窗，耗時 \(ContinuousClock.now - start, privacy: .public)")

        // 音樂 App、行事曆沒有視窗時仍顯示面板：播放列與行程本身就有用
        if windows.isEmpty && !settings.showsEmptyState && MediaPlayer(bundleID: app.bundleIdentifier) == nil && agenda == nil {
            // 就地更新（剛關掉最後一個視窗）時直接收起；途中擦過的空 App 則給寬限
            if previousOrder != nil { hide() } else { dismissForUnpreviewableItem() }
            return
        }

        let screen = screen(near: item.frame)
        let dockPrefs = DockPreferences.current
        let edge = dockPrefs.edge
        let model = PreviewModel(
            app: app, windows: windows, agenda: agenda,
            thumbnail: { [thumbnails] in thumbnails.cached($0)?.image },
            thumbnailHeight: settings.thumbnailHeight,
            showsTitles: settings.showsTitles,
            edge: edge,
            screenSize: screen.visibleFrame.size
        )
        // 延遲期間就開始拍：面板出現時縮圖已經是新的
        let maxPixelWidth = Int(settings.thumbnailHeight * PanelGeometry.maxAspect * screen.backingScaleFactor)
        thumbnails.capture(windows, maxPixelWidth: maxPixelWidth) { [weak self, weak model] id, thumbnail in
            model?.apply(thumbnail.image, to: id)
            self?.markReadyIfComplete()
        }
        await presentAfterDelay(model, item: item, start: start, delay: delay, dockPrefs: dockPrefs, screen: screen)
    }

    /// 接上動作、等滿懸停延遲後顯示面板。
    private func presentAfterDelay(
        _ model: PreviewModel, item: DockItem, start: ContinuousClock.Instant, delay: Duration,
        dockPrefs: DockPreferences = .current, screen: NSScreen? = nil
    ) async {
        model.actions = makeActions(for: model)
        if let media = model.media { connect(media) }
        if let agenda = model.agenda { connect(agenda) }

        let remaining = delay - (ContinuousClock.now - start)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        guard !Task.isCancelled, hoveredItem != nil || isMouseInPanel else { return }

        present(model, icon: item.frame, dockPrefs: dockPrefs, screen: screen ?? self.screen(near: item.frame))
        log.notice("預覽 \(model.appName, privacy: .public)（\(model.cards.count) 個視窗）顯示耗時 \(ContinuousClock.now - start, privacy: .public)")
    }

    private func present(_ model: PreviewModel, icon axFrame: CGRect, dockPrefs: DockPreferences, screen: NSScreen) {
        self.model = model
        if metrics?.title == hoveredItem?.title { metrics?.presentedAt = .now }
        currentPID = model.app?.processIdentifier
        observeCalendarChanges(model.agenda != nil)

        // hover 事件當下的圖示位置可能還在放大/滑出動畫中，顯示前再向 Dock 查一次即時位置
        var iconFrame = axFrame
        if let live = dockObserver?.currentItem(), live.title == hoveredItem?.title {
            iconFrame = live.frame
        }
        anchorIcon = iconFrame

        // 每份新內容給新的 identity：否則 SwiftUI 會把它當成舊視圖的更新，位置沒變的卡片不會回報位置，
        // 就地更新（縮小/關閉視窗後）的新卡片位置全是 0，滑過追蹤就找不到卡片
        let generation = UITestProbe.isEnabled ? UITestProbe.beginGeneration() : 0
        hostingView.rootView = AnyView(
            PreviewView(model: model)
                .environment(\.probeGeneration, generation)
                .id(ObjectIdentifier(model))
        )
        let size = hostingView.fittingSize
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let icon = PanelGeometry.cocoaRect(fromAX: iconFrame, primaryScreenHeight: primaryHeight)
        let edge = dockPrefs.edge
        let frame = PanelGeometry.panelFrame(
            size: size, icon: icon, edge: edge, screen: screen.frame,
            dockExtent: dockPrefs.hoveredItemExtent,
            labelClearance: labelClearance(edge: edge, title: hoveredItem?.title ?? model.appName)
        )

        if panel.isVisible {
            panel.setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            installMonitors()
        }
        dockBand = PanelGeometry.dockBand(panel: frame, edge: edge, screen: screen.frame)
        corridor = PanelGeometry.corridor(
            panel: frame, icon: icon, edge: edge, screen: screen.frame, dockExtent: dockPrefs.hoveredItemExtent
        )
        dockRow = PanelGeometry.dockRow(icon: icon, edge: edge, screen: screen.frame, dockExtent: dockPrefs.hoveredItemExtent)
        markReadyIfComplete()
        // 內容替換後（例如縮小/關閉視窗後就地更新），等卡片完成排版再依游標位置標出滑過的卡片
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hostingView.reportCurrentMouseLocation()
            if self.panel.frame.contains(NSEvent.mouseLocation) { self.setHoverPolling(true) }
        }
    }

    /// 要讓出的 Dock 名稱標籤空間：底部 Dock 為標籤高度；側邊 Dock 的標籤在圖示旁，寬度隨 App 名稱而變。
    private func labelClearance(edge: DockEdge, title: String) -> CGFloat {
        guard edge != .bottom else { return PanelGeometry.dockLabelHeight }
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width
        return textWidth.rounded(.up) + 32
    }

    /// 縮圖全部到齊且面板已顯示時，記下就緒時間（僅供量測）。
    private func markReadyIfComplete() {
        guard let model, metrics?.presentedAt != nil, metrics?.readyAt == nil,
              model.cards.allSatisfy({ $0.thumbnail != nil }) else { return }
        metrics?.readyAt = .now
    }

    /// 就地更新時保持卡片順序：使用者正在面板上操作，卡片不該因為視窗前後層次改變而換位置
    /// （例如還原縮小的視窗後它會跑到最前面）。新出現的視窗排在最前面，其餘沿用原順序。
    nonisolated static func keepingOrder(_ windows: [WindowInfo], previous: [CGWindowID]) -> [WindowInfo] {
        let rank = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($1, $0) })
        return windows.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? -1, r = rank[rhs.element.id] ?? -1
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 視窗被關閉/縮小後，就地重新整理同一個 App 的內容（保持面板開啟）。
    private func refresh(after delay: Duration = .milliseconds(180)) {
        guard let model else { return }
        let app = model.app
        let item = DockItem(title: model.appName, appURL: model.appURL, frame: anchorIcon)
        let order = model.cards.map(\.id)
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, app?.isTerminated != true else { self?.hide(); return }
            self.currentPID = nil
            await self.prepareAndShow(app: app, item: item, delay: .zero, previousOrder: order)
        }
    }

    // MARK: - 滑過追蹤保險

    private var hoverPollTimer: Timer?

    /// 游標在面板內時，以 20Hz 輪詢游標位置作為保險：系統忙碌時偶爾會漏掉單一滑鼠移動事件，
    /// 滑過的卡片就不會浮現按鈕。只在游標位於面板內時執行，其餘時間完全不跑。
    private func setHoverPolling(_ enabled: Bool) {
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
        guard enabled else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hostingView.reportCurrentMouseLocation() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        hoverPollTimer = timer
    }

    // MARK: - 隱藏

    private func mouseInPanelChanged(_ inside: Bool) {
        isMouseInPanel = inside
        if inside { cancelPendingHide() } else { scheduleHide() }
    }

    private func cancelPendingHide() {
        hideTask?.cancel()
        isHidePending = false
    }

    /// 游標移到沒有預覽可顯示的圖示（未執行、沒有視窗）。
    /// 面板未顯示時直接收起；已顯示時改走寬限收起——開放大效果時，游標從圖示往面板移動途中常會擦過隔壁圖示，
    /// 立刻收起會讓面板在使用者眼前消失。若游標確實停在該圖示上，寬限到期後仍會收起。
    private func dismissForUnpreviewableItem() {
        guard panel.isVisible else { hide(); return }
        isHoveredItemPreviewable = false
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        isHidePending = true
        hideTask = Task { [weak self, hideGrace] in
            try? await Task.sleep(for: hideGrace)
            guard let self, !Task.isCancelled else { return }
            self.isHidePending = false
            guard !self.isCursorOverPanelOrDock else { return }
            self.hide()
        }
    }

    /// 立即隱藏面板並取消所有進行中的工作。
    func hide() {
        cancelPendingHide()
        showTask?.cancel()
        thumbnails.cancelInteractive()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        setHoverPolling(false)
        hostingView.rootView = AnyView(EmptyView())
        model = nil
        currentPID = nil
        observeCalendarChanges(false)
        isMouseInPanel = false
        removeMonitors()
    }

    /// 面板顯示期間才掛上的全域監聽（隱藏時移除，閒置零成本）：
    /// - 點擊面板外（含 Dock 圖示）→ 立即收起
    /// - 游標離開「面板＋Dock 帶狀區」→ 寬限後收起。
    ///   為什麼需要：Dock 設為自動隱藏時，游標快速離開後 Dock 不一定會發出「取消選取」通知，
    ///   只靠 AX 事件面板會卡住不收。全域監聽只收到「其他 App」的事件，游標在面板上時由追蹤區負責。
    private func installMonitors() {
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
        if moveMonitor == nil {
            moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMovedOutside() }
            }
        }
    }

    /// 游標是否仍在面板上、正從圖示往面板移動，或仍停在 Dock 上可預覽的 App 圖示上
    /// （以游標實際位置為準，不只信任 Dock 事件）。
    /// Dock 的選取狀態只在圖示列內採信：游標離開圖示後 Dock 常不發取消選取（見 `PanelGeometry.dockRow`）。
    private var isCursorOverPanelOrDock: Bool {
        let location = NSEvent.mouseLocation
        if isMouseInPanel || panel.frame.contains(location) || corridor.contains(location) { return true }
        return hoveredItem != nil && isHoveredItemPreviewable && dockRow.contains(location)
    }

    private func mouseMovedOutside() {
        let location = NSEvent.mouseLocation
        // 游標離開帶狀區：Dock 的選取狀態可能已過時，視同游標已離開圖示
        if !dockBand.contains(location) { hoveredItem = nil }
        guard !isCursorOverPanelOrDock else { return }
        // 移動事件很密集：已有排定的收起就不要重設計時，否則邊移動邊重置永遠收不起來
        if !isHidePending { scheduleHide() }
    }

    private func removeMonitors() {
        for monitor in [clickMonitor, moveMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        clickMonitor = nil
        moveMonitor = nil
    }

    // MARK: - 動作

    private func makeActions(for model: PreviewModel) -> PreviewActions {
        guard let app = model.app else {
            // App 未執行（只顯示行程）：只有「打開 App」可用
            let url = model.appURL
            return PreviewActions(newWindow: { [weak self] in
                self?.hide()
                if let url { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
            })
        }
        return PreviewActions(
            focus: { [weak self] card in
                self?.hide()
                if card.window.isClosed {
                    WindowActions.reopen(app)
                } else {
                    WindowActions.focus(card.window)
                }
            },
            close: { [weak self] card in
                if WindowActions.close(card.window) {
                    self?.thumbnails.purge(windowID: card.id)
                    self?.refresh(after: .milliseconds(250))
                }
            },
            minimize: { [weak self] card in
                if WindowActions.toggleMinimize(card.window) { self?.refresh() }
            },
            toggleFullScreen: { [weak self] card in
                self?.hide()
                WindowActions.focus(card.window)
                WindowActions.toggleFullScreen(card.window)
            },
            hideApp: { [weak self] in
                self?.hide()
                WindowActions.toggleHidden(app)
            },
            quitApp: { [weak self] in
                self?.hide()
                WindowActions.quit(app)
            },
            newWindow: { [weak self] in
                self?.hide()
                WindowActions.newWindow(app)
            }
        )
    }

    // MARK: - 播放列

    /// 接上播放列：查詢一次目前狀態（不會跳出授權詢問），按鈕送出指令後再更新。
    /// 只在面板建立時與按下按鈕後查詢，不輪詢——面板顯示期間換歌不會自動更新，換取閒置零成本。
    private func connect(_ media: MediaBarModel) {
        let player = media.player
        media.send = { [weak media] command in
            Task { [weak media] in
                let status = await MediaController.send(command, to: player)
                media?.status = status
                // 換歌後 App 回報新歌名需要一點時間（Spotify 實測可能先回舊歌），稍後再查一次
                guard case .track = status else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard media != nil else { return }
                let refreshed = await MediaController.status(of: player)
                media?.status = refreshed
            }
        }
        Task { [weak media] in
            let status = await MediaController.status(of: player)
            media?.status = status
        }
    }

    // MARK: - 行程

    /// 這個 App 是否要顯示行程區塊（「行事曆」且設定開啟）。
    private func showsAgenda(for appURL: URL?) -> Bool {
        guard settings.showsCalendarAgenda, let appURL else { return false }
        return Bundle(url: appURL)?.bundleIdentifier == CalendarAgenda.calendarBundleID
    }

    /// 接上行程區塊的動作。
    private func connect(_ agenda: AgendaModel) {
        agenda.open = { [weak self] event in
            self?.hide()
            CalendarAgenda.open(event)
        }
        agenda.join = { [weak self] event in
            self?.hide()
            if let url = event.meetingURL { NSWorkspace.shared.open(url) }
        }
        agenda.requestAccess = { [weak self] in
            Task { [weak self] in
                _ = await CalendarAgenda.requestAccess()
                // 授權後行數會變，面板大小要重算：走就地更新重建內容
                self?.refresh(after: .zero)
            }
        }
        agenda.openSettings = { [weak self] in
            self?.hide()
            CalendarAgenda.openPrivacySettings()
        }
    }

    /// 面板顯示行程期間監聽行事曆資料變動（新增／修改行程、同步完成），變動時就地更新；面板收起即移除。
    private func observeCalendarChanges(_ enabled: Bool) {
        if !enabled {
            if let calendarObserver { NotificationCenter.default.removeObserver(calendarObserver) }
            calendarObserver = nil
            return
        }
        guard calendarObserver == nil else { return }
        calendarObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(after: .milliseconds(100)) }
        }
    }

    // MARK: - 工具

    /// 以 bundle 位置找出對應的執行中 App。
    private func runningApp(for item: DockItem) -> NSRunningApplication? {
        guard let url = item.appURL else { return nil }
        let path = url.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.resolvingSymlinksInPath().path == path
        }
    }

    /// 找出 Dock 圖示所在的螢幕（多螢幕時 Dock 可能在任一螢幕上；滑出途中圖示可能還在螢幕外，取最近者）。
    private func screen(near axFrame: CGRect) -> NSScreen {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let icon = PanelGeometry.cocoaRect(fromAX: axFrame, primaryScreenHeight: primaryHeight)
        let index = PanelGeometry.nearestScreen(to: CGPoint(x: icon.midX, y: icon.midY), in: screens.map(\.frame))
        return index.map { screens[$0] } ?? NSScreen.main ?? screens[0]
    }
}
