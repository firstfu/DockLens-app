//
//  PanelGeometry.swift
//  DockLens
//
//  預覽面板的純幾何計算（座標轉換、卡片尺寸、換行分組、面板定位）。
//  刻意與 UI 分離成無副作用的純函式，方便單元測試，也讓面板尺寸在縮圖拍好之前就能確定——
//  縮圖逐張串流進來時面板不會跳動。
//

import CoreGraphics

nonisolated enum DockEdge: String, Sendable {
    case bottom, left, right
}

nonisolated enum PanelGeometry {
    /// 卡片最窄/最寬相對於高度的比例（極端長寬比的視窗會被裁成這個範圍內，以 aspect-fit 顯示）
    static let minAspect: CGFloat = 0.75
    static let maxAspect: CGFloat = 2.0

    // MARK: - Dock 版面常數
    // macOS 27 實測（tilesize 28、largesize 75、底部 Dock）：放大圖示的 AX 框高 89 = 75 + 14、
    // 下緣距螢幕底 5pt；Dock 名稱標籤（含箭頭）頂端在放大圖示框之上 26pt。

    /// 圖示框與螢幕邊的距離
    static let dockEdgeInset: CGFloat = 5
    /// 圖示框比圖示本身多出的留白
    static let dockItemPadding: CGFloat = 14
    /// Dock 名稱標籤（含箭頭）的高度
    static let dockLabelHeight: CGFloat = 26

    /// 游標所在圖示「放大且靜止」時，距 Dock 所在螢幕邊的厚度。
    /// 用偏好推算而非讀即時位置：Dock 自動隱藏滑出、放大動畫進行中時，即時位置會偏低，面板就會壓到 Dock 上。
    static func dockItemExtent(tileSize: CGFloat, largeSize: CGFloat, magnification: Bool) -> CGFloat {
        dockEdgeInset + (magnification ? max(tileSize, largeSize) : tileSize) + dockItemPadding
    }

    /// AX 座標（主螢幕左上為原點、Y 向下）轉成 Cocoa 座標（主螢幕左下為原點、Y 向上）。
    /// - Parameters:
    ///   - rect: AX 座標矩形
    ///   - primaryScreenHeight: 主螢幕（`NSScreen.screens[0]`）高度
    static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 依視窗長寬比計算縮圖區大小（高度固定、寬度隨比例並夾在合理範圍）。
    static func thumbnailSize(aspectRatio: CGFloat, height: CGFloat) -> CGSize {
        let clamped = min(max(aspectRatio, minAspect), maxAspect)
        return CGSize(width: (height * clamped).rounded(), height: height)
    }

    /// 把卡片依序分組成列（或欄）：每組總長度不超過 `maxLength`，至少放一張。
    /// - Parameters:
    ///   - lengths: 每張卡片在主軸上的長度
    ///   - maxLength: 單組可用的最大長度
    ///   - spacing: 卡片間距
    /// - Returns: 每組包含的卡片索引
    static func group(lengths: [CGFloat], maxLength: CGFloat, spacing: CGFloat) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, length) in lengths.enumerated() {
            let needed = current.isEmpty ? length : used + spacing + length
            if !current.isEmpty && needed > maxLength {
                groups.append(current)
                current = [index]
                used = length
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// 計算面板位置：放在 Dock 圖示（及其名稱標籤）外側、朝螢幕內側展開，並夾在螢幕範圍內。
    /// - Parameters:
    ///   - size: 面板尺寸
    ///   - icon: Dock 圖示外框（Cocoa 座標，可能是動畫中的即時位置）
    ///   - edge: Dock 所在邊
    ///   - screen: 圖示所在螢幕的完整外框（Cocoa 座標）
    ///   - dockExtent: 放大圖示靜止時距螢幕邊的厚度（見 `dockItemExtent`）；與即時位置取較外側者
    ///   - labelClearance: 要讓出的 Dock 名稱標籤空間（底部 Dock 為標籤高度、側邊 Dock 為標籤寬度）
    ///   - gap: 與標籤之間的距離
    ///   - margin: 面板與螢幕邊緣的最小距離
    /// - Returns: 面板 frame（Cocoa 座標，已對齊整數像素）
    static func panelFrame(
        size: CGSize, icon: CGRect, edge: DockEdge, screen: CGRect,
        dockExtent: CGFloat = 0, labelClearance: CGFloat = 0,
        gap: CGFloat = 6, margin: CGFloat = 8
    ) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .bottom:
            let base = max(screen.minY + dockExtent, icon.maxY)
            origin = CGPoint(x: icon.midX - size.width / 2, y: base + labelClearance + gap)
        case .left:
            let base = max(screen.minX + dockExtent, icon.maxX)
            origin = CGPoint(x: base + labelClearance + gap, y: icon.midY - size.height / 2)
        case .right:
            let base = min(screen.maxX - dockExtent, icon.minX)
            origin = CGPoint(x: base - labelClearance - gap - size.width, y: icon.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.minX + margin), screen.maxX - margin - size.width)
        origin.y = min(max(origin.y, screen.minY + margin), screen.maxY - margin - size.height)
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// Dock 帶狀區：從螢幕邊延伸到面板內緣，涵蓋圖示、名稱標籤與兩者之間的空隙。
    /// 游標在此區或面板內時不收起面板，從圖示移往面板途中不會誤觸收起。
    static func dockBand(panel: CGRect, edge: DockEdge, screen: CGRect) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: max(0, panel.minY - screen.minY) + 2)
        case .left: CGRect(x: screen.minX, y: screen.minY, width: max(0, panel.minX - screen.minX) + 2, height: screen.height)
        case .right: CGRect(x: panel.maxX - 2, y: screen.minY, width: max(0, screen.maxX - panel.maxX) + 2, height: screen.height)
        }
    }

    /// 通道：圖示外緣到面板之間、寬度涵蓋圖示與面板的區域，即游標從圖示移往面板的路徑（含 Dock 名稱標籤）。
    /// 游標在此區時不收起面板。刻意不含圖示列本身：游標停在 Dock 空隙或其他圖示上時，仍以 Dock 事件為準。
    /// - Parameters:
    ///   - panel: 面板外框（Cocoa 座標）
    ///   - icon: 錨定的 Dock 圖示外框（Cocoa 座標）
    ///   - edge: Dock 所在邊
    ///   - screen: 圖示所在螢幕的完整外框（Cocoa 座標）
    ///   - dockExtent: 放大圖示靜止時距螢幕邊的厚度（與 `panelFrame` 同一口徑）
    ///   - tolerance: 往圖示方向多涵蓋的距離，吸收 Dock 判定範圍與 AX 外框的誤差
    static func corridor(
        panel: CGRect, icon: CGRect, edge: DockEdge, screen: CGRect,
        dockExtent: CGFloat = 0, tolerance: CGFloat = 4
    ) -> CGRect {
        switch edge {
        case .bottom:
            let base = max(screen.minY + dockExtent, icon.maxY) - tolerance
            let minX = min(panel.minX, icon.minX), maxX = max(panel.maxX, icon.maxX)
            return CGRect(x: minX, y: base, width: maxX - minX, height: max(0, panel.minY - base) + 2)
        case .left:
            let base = max(screen.minX + dockExtent, icon.maxX) - tolerance
            let minY = min(panel.minY, icon.minY), maxY = max(panel.maxY, icon.maxY)
            return CGRect(x: base, y: minY, width: max(0, panel.minX - base) + 2, height: maxY - minY)
        case .right:
            let base = min(screen.maxX - dockExtent, icon.minX) + tolerance
            let minY = min(panel.minY, icon.minY), maxY = max(panel.maxY, icon.maxY)
            return CGRect(x: panel.maxX - 2, y: minY, width: max(0, base - panel.maxX) + 2, height: maxY - minY)
        }
    }

    /// 圖示列：螢幕邊到「放大圖示靜止時的外緣」的整條區域（與 `corridor` 的起點同一口徑）。
    /// 為什麼要跟帶狀區分開：實測游標離開圖示往上移（名稱標籤區）或沿螢幕邊走遠時，Dock **不會**發取消選取，
    /// 選取狀態會一直停在原圖示上。若以整條帶狀區＋「Dock 仍有選取」判斷游標在 Dock 上，
    /// 游標停在螢幕底部任何位置面板都收不起來；只在圖示列內才信任 Dock 的選取狀態。
    /// - Parameters:
    ///   - icon: 錨定的 Dock 圖示外框（Cocoa 座標）
    ///   - edge: Dock 所在邊
    ///   - screen: 圖示所在螢幕的完整外框（Cocoa 座標）
    ///   - dockExtent: 放大圖示靜止時距螢幕邊的厚度（見 `dockItemExtent`）
    static func dockRow(icon: CGRect, edge: DockEdge, screen: CGRect, dockExtent: CGFloat = 0) -> CGRect {
        switch edge {
        case .bottom:
            let base = max(screen.minY + dockExtent, icon.maxY)
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: base - screen.minY)
        case .left:
            let base = max(screen.minX + dockExtent, icon.maxX)
            return CGRect(x: screen.minX, y: screen.minY, width: base - screen.minX, height: screen.height)
        case .right:
            let base = min(screen.maxX - dockExtent, icon.minX)
            return CGRect(x: base, y: screen.minY, width: screen.maxX - base, height: screen.height)
        }
    }

    /// 找出最靠近指定點的螢幕。自動隱藏的 Dock 滑出途中，圖示可能還在螢幕外，不能只用「包含」判斷。
    static func nearestScreen(to point: CGPoint, in screens: [CGRect]) -> Int? {
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        return screens.indices.min { distance(screens[$0]) < distance(screens[$1]) }
    }
}
