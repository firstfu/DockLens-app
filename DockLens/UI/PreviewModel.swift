//
//  PreviewModel.swift
//  DockLens
//
//  預覽面板的資料模型。每張卡片是獨立的 @Observable 物件：縮圖串流進來時只有該卡片重繪，
//  不會牽動整個面板（SwiftUI Observation 以屬性為單位追蹤依賴）。
//

import AppKit
import Observation
import SwiftUI

/// 單一視窗卡片。
@Observable
final class WindowCard: Identifiable {
    let id: CGWindowID
    var window: WindowInfo
    /// 縮圖；尚未拍到時為 nil（顯示 App 圖示佔位）
    var thumbnail: CGImage?
    /// 縮圖區尺寸（points），建立時依視窗長寬比決定、之後不變
    let thumbnailSize: CGSize
    /// 游標是否停在此卡片上（由 PreviewController 依自行追蹤的游標位置設定）
    var isHovered = false
    /// 卡片在面板中的位置（面板內容座標）；只供滑過判斷，變動時不需重繪
    @ObservationIgnored var frameInPanel: CGRect = .zero

    init(window: WindowInfo, thumbnail: CGImage?, thumbnailSize: CGSize) {
        self.id = window.id
        self.window = window
        self.thumbnail = thumbnail
        self.thumbnailSize = thumbnailSize
    }
}

/// 面板上使用者可觸發的動作（由 PreviewController 實作）。
struct PreviewActions {
    var focus: (WindowCard) -> Void = { _ in }
    var close: (WindowCard) -> Void = { _ in }
    var minimize: (WindowCard) -> Void = { _ in }
    var toggleFullScreen: (WindowCard) -> Void = { _ in }
    var hideApp: () -> Void = {}
    var quitApp: () -> Void = {}
    var newWindow: () -> Void = {}
}

/// 音樂 App 的播放列狀態（Spotify、音樂）。
@Observable
final class MediaBarModel {
    let player: MediaPlayer
    var status: MediaStatus = .loading
    /// 送出播放指令（由 PreviewController 實作）
    @ObservationIgnored var send: (MediaCommand) -> Void = { _ in }

    init(player: MediaPlayer) {
        self.player = player
    }
}

@Observable
final class PreviewModel {
    let app: NSRunningApplication
    let appName: String
    let appIcon: NSImage
    let cards: [WindowCard]
    /// 分組後的卡片（列或欄），版面在建立時就算好
    let groups: [[WindowCard]]
    /// `.horizontal`：Dock 在底部，卡片橫向排、多列往上疊；`.vertical`：Dock 在側邊，卡片直向排
    let axis: Axis
    let showsTitles: Bool
    /// 音樂 App 才有的播放列；其他 App 為 nil
    let media: MediaBarModel?
    @ObservationIgnored var actions = PreviewActions()

    /// 用 id 快速找卡片，縮圖回呼時使用
    @ObservationIgnored private let cardByID: [CGWindowID: WindowCard]

    static let spacing: CGFloat = 12

    /// 建立模型並完成版面分組。
    /// - Parameters:
    ///   - app: 目標 App
    ///   - windows: 已排序的視窗
    ///   - thumbnail: 查詢快取縮圖的函式（讓面板一出現就有畫面）
    ///   - thumbnailHeight: 縮圖高度
    ///   - showsTitles: 是否顯示標題
    ///   - edge: Dock 位置
    ///   - screenSize: 可用螢幕尺寸，用於換行
    init(
        app: NSRunningApplication, windows: [WindowInfo],
        thumbnail: (CGWindowID) -> CGImage?,
        thumbnailHeight: CGFloat, showsTitles: Bool, edge: DockEdge, screenSize: CGSize
    ) {
        self.app = app
        self.appName = app.localizedName ?? "App"
        self.appIcon = app.icon ?? NSWorkspace.shared.icon(for: .application)
        self.showsTitles = showsTitles
        self.axis = edge == .bottom ? .horizontal : .vertical
        let media = MediaPlayer(bundleID: app.bundleIdentifier).map(MediaBarModel.init)
        self.media = media

        let cards = windows.map { window in
            WindowCard(
                window: window,
                thumbnail: thumbnail(window.id),
                thumbnailSize: PanelGeometry.thumbnailSize(aspectRatio: window.aspectRatio, height: thumbnailHeight)
            )
        }
        self.cards = cards
        self.cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })

        // 面板最多佔螢幕 90%；卡片在主軸上的長度 = 橫排用寬、直排用高（含標題列）
        let lengths: [CGFloat]
        let maxLength: CGFloat
        if edge == .bottom {
            lengths = cards.map { $0.thumbnailSize.width + WindowCardView.horizontalPadding * 2 }
            maxLength = screenSize.width * 0.9 - 2 * PreviewView.padding
        } else {
            lengths = cards.map { _ in WindowCardView.totalHeight(thumbnailHeight: thumbnailHeight, showsTitles: showsTitles) }
            maxLength = screenSize.height * 0.85 - 2 * PreviewView.padding - PreviewView.headerHeight
                - (media != nil ? MediaBarView.height + PreviewView.sectionSpacing : 0)
        }
        self.groups = PanelGeometry.group(lengths: lengths, maxLength: maxLength, spacing: Self.spacing)
            .map { $0.map { cards[$0] } }
    }

    /// 設定游標所在的卡片；只更新狀態有變的兩張卡片，其餘卡片不重繪。
    func setHoveredCard(at point: CGPoint?) {
        let target = point.flatMap { point in cards.first { $0.frameInPanel.contains(point) } }
        guard target?.id != hoveredID else { return }
        if let hoveredID { cardByID[hoveredID]?.isHovered = false }
        target?.isHovered = true
        hoveredID = target?.id
    }

    @ObservationIgnored private var hoveredID: CGWindowID?

    /// 套用新拍到的縮圖。
    func apply(_ image: CGImage, to windowID: CGWindowID) {
        cardByID[windowID]?.thumbnail = image
    }
}
