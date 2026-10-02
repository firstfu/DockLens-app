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
        WindowCardView(card: card, appIcon: model.appIcon, showsTitles: model.showsTitles, actions: model.actions)
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
            HeaderButton(symbol: "plus", help: model.app == nil ? "打開 App" : "新增視窗", action: model.actions.newWindow)
                .probe("header.new")
            // App 未執行（只顯示行程）時沒有東西可隱藏或結束
            if model.app != nil {
                HeaderButton(symbol: "eye.slash", help: "隱藏 App", action: model.actions.hideApp)
                    .probe("header.hide")
                HeaderButton(symbol: "power", help: "結束 App", role: .destructive, action: model.actions.quitApp)
                    .probe("header.quit")
            }
        }
        .frame(height: Self.headerHeight)
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
    static let minWidth: CGFloat = 240
    let media: MediaBarModel

    var body: some View {
        Color.clear
            .frame(minWidth: Self.minWidth, maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay(alignment: .leading) {
                HStack(spacing: 6) {
                    MediaButton(symbol: "backward.fill", help: "上一首") { media.send(.previous) }
                        .probe("media.previous")
                    MediaButton(symbol: isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "暫停" : "播放", prominent: true) {
                        media.send(.playPause)
                    }
                    .probe("media.playpause")
                    MediaButton(symbol: "forward.fill", help: "下一首") { media.send(.next) }
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
                    .truncationMode(.tail)
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
        case .loading: "讀取中…"
        case .needsPermission: "按播放鈕以允許控制\(media.player.displayName)"
        case .denied: "未允許控制\(media.player.displayName)"
        case .stopped: "未在播放"
        case .track(let track): track.title
        case .unavailable: "無法讀取播放狀態"
        }
    }

    private var subtitle: String? {
        switch media.status {
        case .track(let track): track.artist.isEmpty ? nil : track.artist
        case .denied: "系統設定 › 隱私權與安全性 › 自動化"
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
    let help: LocalizedStringKey
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
    let actions: PreviewActions

    private var isHovering: Bool { card.isHovered }

    var body: some View {
        VStack(spacing: Self.titleSpacing) {
            thumbnail
                .frame(width: card.thumbnailSize.width, height: card.thumbnailSize.height)
                .probe("card.\(card.id)")
                .overlay(alignment: .topLeading) {
                    if isHovering && card.window.ax != nil { controls.padding(7) }
                }
                .overlay(alignment: .bottomTrailing) { badge.padding(6) }
            if showsTitles {
                Text(card.window.title.isEmpty ? "未命名視窗" : card.window.title)
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
        .help(card.window.isClosed ? "點擊重新打開" : card.window.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.window.title.isEmpty ? "未命名視窗" : card.window.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.focus(card) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = card.thumbnail {
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

    private var controls: some View {
        HStack(spacing: 6) {
            TrafficLight(color: .red, symbol: "xmark", help: "關閉視窗") { actions.close(card) }
                .probe("close.\(card.id)")
            TrafficLight(color: .yellow, symbol: card.window.isMinimized ? "plus" : "minus",
                         help: card.window.isMinimized ? "還原視窗" : "縮到 Dock") { actions.minimize(card) }
                .probe("minimize.\(card.id)")
            TrafficLight(color: .green, symbol: "arrow.up.left.and.arrow.down.right", help: "全螢幕") {
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
    let help: LocalizedStringKey
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
    static func sample(edge: DockEdge = .bottom) -> PreviewModel {
        let specs: [(String, CGSize, Bool, Bool)] = [
            ("DockLens — PreviewView.swift", CGSize(width: 1440, height: 900), false, false),
            ("設計稿 v3.fig", CGSize(width: 1280, height: 800), false, false),
            ("終端機 — zsh", CGSize(width: 800, height: 600), true, false),
            ("文件 — 其他桌面", CGSize(width: 1200, height: 900), false, true),
        ]
        let windows = specs.enumerated().map { index, spec in
            WindowInfo(
                id: CGWindowID(index + 1), pid: 0, title: spec.0,
                frame: CGRect(origin: .zero, size: spec.1),
                isMinimized: spec.2, isOnOtherSpace: spec.3, ax: nil
            )
        }
        let hues: [CGFloat] = [0.6, 0.08, 0.35, 0.8]
        return PreviewModel(
            app: .current, windows: windows,
            thumbnail: { id in sampleImage(hue: hues[Int(id - 1) % hues.count]) },
            thumbnailHeight: 150, showsTitles: true, edge: edge,
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
