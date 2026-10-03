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
                // 音樂 App 沒有視窗時仍有播放列可用、行事曆仍有行程，不再顯示「沒有開啟的視窗」
                if model.media == nil && model.agenda == nil { emptyState }
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
    /// 產生示範用模型：數個不同長寬比、狀態的假視窗。
    /// - Parameters:
    ///   - edge: Dock 位置
    ///   - showsThumbnails: false 時為無縮圖模式
    static func sample(edge: DockEdge = .bottom, showsThumbnails: Bool = true) -> PreviewModel {
        // (標題, 尺寸, 已縮小, 其他桌面, 已關閉)：涵蓋每一種狀態標籤，檢查翻譯後標籤會不會撐破卡片
        let specs: [(String, CGSize, Bool, Bool, Bool)] = [
            ("DockLens — PreviewView.swift", CGSize(width: 1440, height: 900), false, false, false),
            ("Design v3.fig", CGSize(width: 1280, height: 800), false, false, false),
            ("Terminal — zsh", CGSize(width: 800, height: 600), true, false, false),
            ("Notes — Desktop 2", CGSize(width: 1200, height: 900), false, true, false),
            ("Inbox", CGSize(width: 900, height: 900), false, false, true),
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
        let hues: [CGFloat] = [0.6, 0.08, 0.35, 0.8, 0.5]
        return PreviewModel(
            app: .current, windows: windows,
            thumbnail: { id in sampleImage(hue: hues[Int(id - 1) % hues.count]) },
            thumbnailHeight: 150, showsTitles: true, showsThumbnails: showsThumbnails, edge: edge,
            screenSize: CGSize(width: 1728, height: 1080)
        )
    }

    /// 畫一張帶標題列與內容區塊的假視窗縮圖。
    private static func sampleImage(hue: CGFloat) -> CGImage? {
        let size = CGSize(width: 480, height: 300)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        let base = NSColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1)
        context.setFillColor(base.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor(hue: hue, saturation: 0.5, brightness: 0.75, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: size.height - 28, width: size.width, height: 28))
        context.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        for row in 0..<5 {
            context.fill(CGRect(x: 24, y: size.height - 70 - CGFloat(row) * 40, width: size.width * (0.8 - CGFloat(row) * 0.1), height: 16))
        }
        return context.makeImage()
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
