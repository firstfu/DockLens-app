//
//  PreviewView.swift
//  DockLens
//
//  預覽面板的 SwiftUI 介面：標頭（App 圖示/名稱/快捷操作）+ 視窗縮圖卡片。
//  外觀採用 macOS 26 的 Liquid Glass（`glassEffect`）。所有尺寸皆為固定值，
//  讓 NSHostingView 算出的面板大小在縮圖串流期間保持不變。
//

import SwiftUI

struct PreviewView: View {
    static let padding: CGFloat = 12
    static let headerHeight: CGFloat = 26
    /// 標頭、播放列、卡片之間的間距
    static let sectionSpacing: CGFloat = 10
    /// 面板內容的座標空間名稱（自我測試換算按鈕位置用）
    nonisolated static let coordinateSpace = "DockLensPanel"

    let model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            header
            if let media = model.media {
                MediaBarView(media: media)
            }
            if let agenda = model.agenda {
                AgendaView(agenda: agenda)
            }
            if model.cards.isEmpty {
                // 音樂 App 沒有視窗時仍有播放列可用、行事曆仍有行程、剛關掉的文件仍可重開，不再顯示「沒有開啟的視窗」
                if model.media == nil && model.agenda == nil && model.closed.isEmpty { emptyState }
            } else if model.axis == .horizontal {
                VStack(alignment: .leading, spacing: PreviewModel.spacing) {
                    ForEach(model.groups.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: PreviewModel.spacing) {
                            ForEach(model.groups[index]) { card in cardView(card) }
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: PreviewModel.spacing) {
                    ForEach(model.groups.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: PreviewModel.spacing) {
                            ForEach(model.groups[index]) { card in cardView(card) }
                        }
                    }
                }
            }
            if !model.closed.isEmpty {
                RecentlyClosedView(entries: model.closed, restore: model.actions.restore)
            }
        }
        .padding(Self.padding)
        .fixedSize()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    private func cardView(_ card: WindowCard) -> some View {
        WindowCardView(card: card, appIcon: model.appIcon, showsTitles: model.showsTitles,
                       showsThumbnails: model.showsThumbnails, actions: model.actions,
                       showsShortcutHints: model.showsShortcutHints)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: model.appIcon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(model.appName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if model.cards.count > 1 {
                Text("\(model.cards.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 16)
            HeaderButton(symbol: "plus", help: model.app == nil ? String(localized: "打開 App") : String(localized: "新增視窗"),
                         action: model.actions.newWindow)
                .probe("header.new")
            // App 未執行（只顯示行程）時沒有東西可隱藏或結束
            if model.app != nil {
                HeaderButton(symbol: "eye.slash", help: withShortcut(String(localized: "隱藏 App"), "H"), action: model.actions.hideApp)
                    .probe("header.hide")
                HeaderButton(symbol: "power", help: withShortcut(String(localized: "結束 App"), "Q"), role: .destructive, action: model.actions.quitApp)
                    .probe("header.quit")
            }
        }
        .frame(height: Self.headerHeight)
    }

    private func withShortcut(_ text: String, _ key: String) -> String {
        PreviewView.withShortcut(text, key, shows: model.showsShortcutHints)
    }

    /// 按鈕提示後附上單鍵快捷鍵，例如「隱藏 App（H）」；括號寫法各語言不同（中日文全形、其他半形），交給翻譯決定。
    /// - Parameters:
    ///   - text: 已翻譯的提示文字
    ///   - key: 快捷鍵字母
    ///   - shows: 是否附上（快捷鍵停用時不附）
    static func withShortcut(_ text: String, _ key: String, shows: Bool) -> String {
        shows ? String(localized: "\(text)（\(key)）", comment: "按鈕提示＋單鍵快捷鍵，例如「隱藏 App（H）」") : text
    }

    private var emptyState: some View {
        Text("沒有開啟的視窗")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(minWidth: 220, minHeight: 44)
    }
}

/// 音樂 App 的播放列：上一首／播放暫停／下一首＋目前歌曲。
/// 高度固定、文字放在 overlay 裡：歌名在面板顯示後才查到，不能讓它撐寬或撐高面板（面板大小在顯示時就算好）。
struct MediaBarView: View {
    static let height: CGFloat = 34
    /// App 沒有視窗時面板只剩標頭，給播放列最小寬度，歌名才不會被截得太短
    static let minWidth: CGFloat = 280
    let media: MediaBarModel

    var body: some View {
        Color.clear
            .frame(minWidth: Self.minWidth, maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                HStack(spacing: 6) {
                    MediaButton(symbol: "backward.fill", help: String(localized: "上一首")) { media.send(.previous) }
                        .probe("media.previous")
                    MediaButton(symbol: isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? String(localized: "暫停") : String(localized: "播放"), prominent: true) {
                        media.send(.playPause)
                    }
                    .probe("media.playpause")
                    MediaButton(symbol: "forward.fill", help: String(localized: "下一首")) { media.send(.next) }
                        .probe("media.next")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .help([title, subtitle].compactMap { $0 }.joined(separator: "\n"))
                    .padding(.leading, 4)
                }
            }
    }

    private var isPlaying: Bool {
        if case .track(let track) = media.status { return track.isPlaying }
        return false
    }

    private var title: String {
        switch media.status {
        case .loading: String(localized: "讀取中…")
        case .needsPermission: String(localized: "按播放鈕以允許控制\(media.player.displayName)", comment: "%@ 為 Spotify 或「音樂」App")
        case .denied: String(localized: "未允許控制\(media.player.displayName)", comment: "%@ 為 Spotify 或「音樂」App")
        case .stopped: String(localized: "未在播放")
        case .track(let track): track.title
        case .unavailable: String(localized: "無法讀取播放狀態")
        }
    }

    private var subtitle: String? {
        switch media.status {
        case .track(let track): track.artist.isEmpty ? nil : track.artist
        case .denied: String(localized: "系統設定 › 隱私權與安全性 › 自動化", comment: "macOS 系統設定的路徑，請用該語言 macOS 的實際名稱")
        default: nil
        }
    }
}

/// 播放列的按鈕；播放／暫停鈕較大以利辨識。
private struct MediaButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 13 : 11, weight: .bold))
                .frame(width: prominent ? 30 : 26, height: prominent ? 30 : 26)
                .foregroundStyle(.primary)
                .background(Circle().fill(.primary.opacity(prominent ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 標頭右側的小圓鈕。
private struct HeaderButton: View {
    let symbol: String
    /// 已翻譯的提示文字（可能附上快捷鍵，所以不是 LocalizedStringKey）
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(role == .destructive && isHovering ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .background(Circle().fill(.primary.opacity(isHovering ? 0.14 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 單一視窗卡片：縮圖 + 標題，滑過時浮現紅黃綠操作鈕。
struct WindowCardView: View {
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 6
    static let titleHeight: CGFloat = 15
    static let titleSpacing: CGFloat = 6

    /// 卡片總高度（直排分欄時用來計算）。
    static func totalHeight(thumbnailHeight: CGFloat, showsTitles: Bool) -> CGFloat {
        thumbnailHeight + verticalPadding * 2 + (showsTitles ? titleHeight + titleSpacing : 0)
    }

    let card: WindowCard
    let appIcon: NSImage
    let showsTitles: Bool
    /// false 為無縮圖模式：卡片內放 App 圖示與標題
    var showsThumbnails = true
    let actions: PreviewActions
    let showsShortcutHints: Bool

    private var isHovering: Bool { card.isHovered }

    var body: some View {
        VStack(spacing: Self.titleSpacing) {
            thumbnail
                .frame(width: card.thumbnailSize.width, height: card.thumbnailSize.height)
                .probe("card.\(card.id)")
                .overlay(alignment: showsThumbnails ? .topLeading : .trailing) {
                    if isHovering && card.window.ax != nil {
                        if showsThumbnails {
                            controls.padding(7)
                        } else {
                            // 長條卡片沒有空角落：浮在右側、墊一層材質，蓋住長標題的尾端時仍看得清楚
                            controls
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.trailing, 8)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsThumbnails { badge.padding(6) }
                }
            if showsTitles {
                Text(card.window.title.isEmpty ? String(localized: "未命名視窗") : card.window.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: card.thumbnailSize.width, height: Self.titleHeight)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(isHovering ? 0.10 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: card.isHovered)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PreviewView.coordinateSpace))
        } action: { frame in
            card.frameInPanel = frame
        }
        .onTapGesture { actions.focus(card) }
        .help(card.window.isClosed ? String(localized: "點擊重新打開") : card.window.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.window.title.isEmpty ? String(localized: "未命名視窗") : card.window.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.focus(card) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if !showsThumbnails {
            listContent
        } else if let image = card.thumbnail {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .opacity(card.window.isMinimized || card.window.isClosed ? 0.55 : 1)
                .scaleEffect(isHovering ? 1.02 : 1)
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.06))
                .overlay {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .opacity(0.85)
                }
        }
    }

    /// 無縮圖模式的卡片內容：App 圖示＋標題（最多兩行）＋狀態（已縮小／其他桌面／已關閉）。
    /// 狀態改成標題下的一行小字，不用縮圖模式的右下角標籤：長條卡片沒有空角落可放。
    private var listContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.window.title.isEmpty ? String(localized: "未命名視窗") : card.window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .lineLimit(statusText == nil ? 2 : 1)
                    .truncationMode(.middle)
                if let statusText {
                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(isHovering ? 0.10 : 0.06))
        )
        .opacity(card.window.isMinimized || card.window.isClosed ? 0.7 : 1)
    }

    /// 無縮圖模式標題下的狀態文字；一般視窗為 nil。
    private var statusText: LocalizedStringKey? {
        if card.window.isClosed { return "已關閉・點擊打開" }
        if card.window.isMinimized { return "已縮小" }
        if card.window.isOnOtherSpace { return "其他桌面" }
        return nil
    }

    @ViewBuilder
    private var badge: some View {
        if card.window.isClosed {
            BadgeLabel(text: "已關閉・點擊打開", symbol: "arrow.uturn.backward")
        } else if card.window.isMinimized {
            BadgeLabel(text: "已縮小", symbol: "arrow.down.right.and.arrow.up.left")
        } else if card.window.isOnOtherSpace {
            BadgeLabel(text: "其他桌面", symbol: "rectangle.split.3x1")
        }
    }

    private func withShortcut(_ text: String, _ key: String) -> String {
        PreviewView.withShortcut(text, key, shows: showsShortcutHints)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            TrafficLight(color: .red, symbol: "xmark", help: withShortcut(String(localized: "關閉視窗"), "W")) { actions.close(card) }
                .probe("close.\(card.id)")
            TrafficLight(color: .yellow, symbol: card.window.isMinimized ? "plus" : "minus",
                         help: withShortcut(card.window.isMinimized ? String(localized: "還原視窗") : String(localized: "縮到 Dock"), "M")) { actions.minimize(card) }
                .probe("minimize.\(card.id)")
            TrafficLight(color: .green, symbol: "arrow.up.left.and.arrow.down.right", help: String(localized: "全螢幕")) {
                actions.toggleFullScreen(card)
            }
            .probe("fullscreen.\(card.id)")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

/// 仿系統紅黃綠燈的小圓鈕。
private struct TrafficLight: View {
    let color: Color
    let symbol: String
    /// 已翻譯的提示文字（可能附上快捷鍵）
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black.opacity(0.6))
                }
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct BadgeLabel: View {
    let text: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .labelStyle(.titleAndIcon)
            // 翻譯後可能比中文長很多（德文、俄文），不換行、太長就截斷，不撐破卡片
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - 自我測試探針

/// 自我測試用：記錄面板上各元件的位置，讓測試能對「真正的按鈕位置」合成點擊。
/// 只在 `--selftest` 時啟用，平常這個修飾器直接回傳原 view，不產生任何開銷。
enum UITestProbe {
    static let isEnabled = CommandLine.arguments.contains("--selftest")
    /// 目前面板內容的世代編號；每次換新內容遞增，測試只讀這一代回報的位置
    private(set) static var currentGeneration = 0
    /// 「世代/鍵值」→ (回報者識別碼, 在面板座標空間（左上為原點）中的外框)
    private static var entries: [String: (owner: UUID, frame: CGRect)] = [:]

    /// 開始新一代內容，並丟棄舊世代的所有紀錄。
    /// 為什麼要分代：面板換內容時，舊視圖在被拆掉前仍可能回報一次舊位置，覆蓋掉新視圖剛回報的位置。
    static func beginGeneration() -> Int {
        currentGeneration += 1
        entries.removeAll()
        return currentGeneration
    }

    static func frame(_ key: String) -> CGRect? { entries["\(currentGeneration)/\(key)"]?.frame }

    static func report(_ key: String, generation: Int, owner: UUID, frame: CGRect) {
        guard generation == currentGeneration else { return }
        entries["\(generation)/\(key)"] = (owner, frame)
    }

    static func remove(_ key: String, generation: Int, owner: UUID) {
        let fullKey = "\(generation)/\(key)"
        if entries[fullKey]?.owner == owner { entries[fullKey] = nil }
    }
}

extension EnvironmentValues {
    /// 面板內容的世代編號（自我測試探針用）
    @Entry var probeGeneration = 0
}

extension View {
    /// 回報此 view 在面板中的位置（僅自我測試時生效）。
    func probe(_ key: String) -> some View {
        modifier(ProbeModifier(key: key))
    }
}

private struct ProbeModifier: ViewModifier {
    let key: String
    @State private var owner = UUID()
    @Environment(\.probeGeneration) private var generation

    func body(content: Content) -> some View {
        if UITestProbe.isEnabled {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(PreviewView.coordinateSpace))
                } action: { frame in
                    UITestProbe.report(key, generation: generation, owner: owner, frame: frame)
                }
                .onDisappear { UITestProbe.remove(key, generation: generation, owner: owner) }
        } else {
            content
        }
    }
}

// MARK: - Xcode Preview（假資料，不需任何權限即可檢視面板外觀）

#if DEBUG
extension PreviewModel {
    /// 產生示範用模型：虛構的「Gallery」App，數個不同狀態（一般、已縮小、其他桌面、已關閉）的視窗。
    /// 用在 Xcode Preview 與 `--render-ui` 產生說明圖；內容完全虛構，不含任何使用者資料。
    /// - Parameters:
    ///   - edge: Dock 位置
    ///   - showsThumbnails: false 時為無縮圖模式
    static func sample(edge: DockEdge = .bottom, showsThumbnails: Bool = true) -> PreviewModel {
        // (標題, 尺寸, 已縮小, 其他桌面, 已關閉, 風景)
        let specs: [(String, CGSize, Bool, Bool, Bool, SampleScene)] = [
            ("Sunrise", CGSize(width: 1440, height: 900), false, false, false, .sunrise),
            ("Forest", CGSize(width: 1280, height: 800), false, false, false, .forest),
            ("Ocean", CGSize(width: 1440, height: 900), false, false, false, .ocean),
            ("Desert", CGSize(width: 1200, height: 800), true, false, false, .desert),
            ("Aurora", CGSize(width: 1280, height: 800), false, true, false, .aurora),
        ]
        let windows = specs.enumerated().map { index, spec in
            var window = WindowInfo(
                id: CGWindowID(index + 1), pid: 0, title: spec.0,
                frame: CGRect(origin: .zero, size: spec.1),
                isMinimized: spec.2, isOnOtherSpace: spec.3, ax: nil
            )
            window.isClosed = spec.4
            return window
        }
        return PreviewModel(
            app: .current, windows: windows,
            thumbnail: { id in specs[Int(id - 1) % specs.count].5.image() },
            thumbnailHeight: 150, showsTitles: true, showsThumbnails: showsThumbnails, edge: edge,
            screenSize: CGSize(width: 1728, height: 1080),
            displayName: "Gallery", icon: SampleScene.appIcon()
        )
    }
}

extension PreviewModel {
    /// 示範用：App 只剩一個「按 ✕ 關掉但 App 仍在執行」的視窗（Notion、Slack 這類），卡片標示已關閉、點一下重新打開。
    /// 已關閉的視窗沒有縮圖（畫面已不在 WindowServer），所以顯示 App 圖示佔位，與實際行為一致。
    static func sampleClosed() -> PreviewModel {
        var window = WindowInfo(id: 1, pid: 0, title: "Sketchbook", frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                                isMinimized: false, isOnOtherSpace: false, ax: nil)
        window.isClosed = true
        return PreviewModel(
            app: .current, windows: [window], thumbnail: { _ in nil },
            thumbnailHeight: 150, showsTitles: true, edge: .bottom,
            screenSize: CGSize(width: 1728, height: 1080),
            displayName: "Gallery", icon: SampleScene.appIcon()
        )
    }
}

extension PreviewModel {
    /// 示範用：兩個開著的視窗，加上剛關掉的三個文件（檔名與資料夾皆虛構），看「最近關閉」區塊的排版。
    static func sampleRecentlyClosed(edge: DockEdge = .bottom, openWindows: Int = 2) -> PreviewModel {
        let scenes: [SampleScene] = [.sunrise, .forest]
        let windows = (0..<openWindows).map { index in
            WindowInfo(id: CGWindowID(index + 1), pid: 0, title: ["Sunrise", "Forest"][index % 2],
                       frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMinimized: false, isOnOtherSpace: false, ax: nil)
        }
        let now = Date.now
        let closed = [
            ClosedWindowEntry(bundleID: "demo", title: "Trip plan.txt", url: URL(fileURLWithPath: "/Users/example/Documents/Trip plan.txt"),
                              closedAt: now.addingTimeInterval(-20)),
            ClosedWindowEntry(bundleID: "demo", title: "Budget 2026.numbers", url: URL(fileURLWithPath: "/Users/example/Documents/Finance/Budget 2026.numbers"),
                              closedAt: now.addingTimeInterval(-5 * 60)),
            ClosedWindowEntry(bundleID: "demo", title: "A very long document name that keeps going and going.md",
                              url: URL(fileURLWithPath: "/Users/example/Projects/Notes/A very long document name that keeps going and going.md"),
                              closedAt: now.addingTimeInterval(-3 * 3600)),
        ]
        return PreviewModel(
            app: .current, windows: windows, closed: closed,
            thumbnail: { id in scenes[Int(id - 1) % scenes.count].image() },
            thumbnailHeight: 150, showsTitles: true, edge: edge,
            screenSize: CGSize(width: 1728, height: 1080),
            displayName: "Gallery", icon: SampleScene.appIcon()
        )
    }
}

/// 示範用的風景縮圖（漸層天空＋太陽＋層疊山丘），用 Core Graphics 畫，不需要任何圖檔。
enum SampleScene {
    case sunrise, forest, ocean, desert, aurora

    /// (天空起點, 中間, 終點, 太陽位置與半徑, 山丘顏色由遠到近)
    private var palette: (sky: [NSColor], sun: (CGFloat, CGFloat, CGFloat), hills: [NSColor]) {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
        switch self {
        case .sunrise: return ([c(255, 176, 120), c(255, 120, 150), c(90, 70, 170)], (0.70, 0.62, 0.11), [c(120, 60, 150), c(80, 40, 120), c(40, 25, 80)])
        case .forest: return ([c(190, 235, 170), c(90, 190, 140), c(20, 90, 90)], (0.76, 0.70, 0.09), [c(40, 130, 90), c(25, 100, 75), c(15, 70, 60)])
        case .ocean: return ([c(120, 200, 255), c(60, 130, 230), c(20, 50, 140)], (0.30, 0.66, 0.09), [c(30, 100, 190), c(20, 70, 160), c(10, 40, 110)])
        case .desert: return ([c(255, 220, 150), c(255, 170, 110), c(190, 90, 90)], (0.52, 0.60, 0.12), [c(205, 120, 80), c(165, 85, 65), c(120, 60, 55)])
        case .aurora: return ([c(20, 30, 70), c(30, 120, 120), c(110, 60, 160)], (0.18, 0.72, 0.05), [c(15, 40, 60), c(10, 28, 45), c(6, 16, 30)])
        }
    }

    func image() -> CGImage? {
        let width = 480, height = 300
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        let p = palette
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: p.sky.map(\.cgColor) as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])
        // 太陽
        context.setFillColor(NSColor(red: 1, green: 0.96, blue: 0.84, alpha: 0.95).cgColor)
        let radius = p.sun.2 * CGFloat(width)
        context.fillEllipse(in: CGRect(x: p.sun.0 * CGFloat(width) - radius, y: p.sun.1 * CGFloat(height) - radius, width: radius * 2, height: radius * 2))
        // 山丘：由遠到近三層
        for (index, color) in p.hills.enumerated() {
            context.setFillColor(color.cgColor)
            let base = CGFloat(height) * (0.38 - CGFloat(index) * 0.11)
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: 0, through: width, by: 8) {
                let t = CGFloat(x)
                context.addLine(to: CGPoint(x: t, y: base + sin(t / 70 + CGFloat(index) * 1.7) * 16 + sin(t / 23 + CGFloat(index)) * 4))
            }
            context.addLine(to: CGPoint(x: CGFloat(width), y: 0))
            context.closePath()
            context.fillPath()
        }
        _ = rect
        return context.makeImage()
    }

    /// 「Gallery」的 App 圖示：圓角漸層底＋太陽＋山丘。
    static func appIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { r in
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 28, dy: 28), xRadius: 110, yRadius: 110)
            NSGradient(colors: [NSColor(red: 1, green: 0.62, blue: 0.4, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.75, alpha: 1)])!.draw(in: path, angle: -60)
            NSColor(white: 1, alpha: 0.92).setFill(); NSBezierPath(ovalIn: NSRect(x: 300, y: 300, width: 80, height: 80)).fill()
            let hills = NSBezierPath()
            hills.move(to: NSPoint(x: 28, y: 150))
            hills.curve(to: NSPoint(x: 260, y: 200), controlPoint1: NSPoint(x: 100, y: 260), controlPoint2: NSPoint(x: 190, y: 120))
            hills.curve(to: NSPoint(x: 484, y: 160), controlPoint1: NSPoint(x: 340, y: 270), controlPoint2: NSPoint(x: 430, y: 200))
            hills.line(to: NSPoint(x: 484, y: 60)); hills.line(to: NSPoint(x: 28, y: 60)); hills.close()
            NSColor(red: 0.22, green: 0.12, blue: 0.45, alpha: 0.95).setFill(); hills.fill()
            return true
        }
    }
}

#Preview("底部 Dock") {
    PreviewView(model: .sample())
        .padding(40)
        .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
}

#Preview("側邊 Dock") {
    PreviewView(model: .sample(edge: .left))
        .padding(40)
        .background(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
}
#endif
