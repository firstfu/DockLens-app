//
//  PanelGeometryTests.swift
//  DockLensTests
//
//  驗證面板幾何計算：座標轉換、卡片尺寸夾限、換行分組、面板定位與螢幕邊界夾限。
//

import CoreGraphics
import Testing
@testable import DockLens

struct PanelGeometryTests {
    @Test func axToCocoaFlipsY() {
        let ax = CGRect(x: 100, y: 1000, width: 60, height: 60)
        let cocoa = PanelGeometry.cocoaRect(fromAX: ax, primaryScreenHeight: 1080)
        #expect(cocoa == CGRect(x: 100, y: 20, width: 60, height: 60))
    }

    @Test(arguments: [(16.0 / 9.0, 267.0), (0.2, 113.0), (5.0, 300.0)])
    func thumbnailWidthIsClamped(aspect: Double, expectedWidth: Double) {
        let size = PanelGeometry.thumbnailSize(aspectRatio: aspect, height: 150)
        #expect(size.height == 150)
        #expect(Double(size.width) == expectedWidth)
    }

    @Test func groupingWrapsWhenExceedingMaxLength() {
        let groups = PanelGeometry.group(lengths: [100, 100, 100, 100], maxLength: 320, spacing: 10)
        #expect(groups == [[0, 1, 2], [3]])
    }

    @Test func oversizedItemGetsItsOwnGroup() {
        let groups = PanelGeometry.group(lengths: [500, 50], maxLength: 300, spacing: 10)
        #expect(groups == [[0], [1]])
    }

    @Test func emptyInputProducesNoGroups() {
        #expect(PanelGeometry.group(lengths: [], maxLength: 100, spacing: 10).isEmpty)
    }

    @Test func bottomDockCentersAboveIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let icon = CGRect(x: 900, y: 10, width: 60, height: 60)
        let frame = PanelGeometry.panelFrame(size: CGSize(width: 400, height: 200), icon: icon, edge: .bottom, screen: screen, gap: 4)
        #expect(frame.midX == icon.midX)
        #expect(frame.minY == icon.maxY + 4)
    }

    @Test func bottomDockClampsToScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let icon = CGRect(x: 10, y: 10, width: 60, height: 60)
        let frame = PanelGeometry.panelFrame(size: CGSize(width: 600, height: 200), icon: icon, edge: .bottom, screen: screen, margin: 8)
        #expect(frame.minX == 8)
    }

    @Test func leftAndRightDocksOpenInward() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 300, height: 400)
        let leftIcon = CGRect(x: 0, y: 500, width: 60, height: 60)
        let left = PanelGeometry.panelFrame(size: size, icon: leftIcon, edge: .left, screen: screen, gap: 4)
        #expect(left.minX == leftIcon.maxX + 4)
        #expect(left.midY == leftIcon.midY)

        let rightIcon = CGRect(x: 1860, y: 500, width: 60, height: 60)
        let right = PanelGeometry.panelFrame(size: size, icon: rightIcon, edge: .right, screen: screen, gap: 4)
        #expect(right.maxX == rightIcon.minX - 4)
    }

    @Test func secondaryScreenWithNegativeOrigin() {
        // 主螢幕左側的副螢幕，x 為負值
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let icon = CGRect(x: -1400, y: 5, width: 50, height: 50)
        let frame = PanelGeometry.panelFrame(size: CGSize(width: 500, height: 180), icon: icon, edge: .bottom, screen: screen, margin: 8)
        #expect(frame.minX == -1432)
        #expect(screen.contains(frame))
    }
}

struct ThumbnailDownscaleTests {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func downscaleKeepsAspectRatio() throws {
        let image = makeImage(width: 1600, height: 1000)
        let scaled = try #require(ThumbnailService.downscale(image, maxPixelWidth: 400))
        #expect(scaled.width == 400)
        #expect(scaled.height == 250)
    }

    @Test func smallImageIsReturnedUnchanged() throws {
        let image = makeImage(width: 300, height: 200)
        let scaled = try #require(ThumbnailService.downscale(image, maxPixelWidth: 400))
        #expect(scaled.width == 300)
    }
}

struct CardOrderTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: "\(id)", frame: .zero, isMinimized: false, isOnOtherSpace: false, ax: nil)
    }

    @Test func refreshKeepsPreviousOrderAndPutsNewWindowsFirst() {
        // 系統最近使用順序：3 被還原到最前、5 是新開的
        let current = [5, 3, 1, 2].map { window(CGWindowID($0)) }
        let ordered = PreviewController.keepingOrder(current, previous: [1, 2, 3])
        #expect(ordered.map(\.id) == [5, 1, 2, 3])
    }

    @Test func closedWindowsSimplyDisappear() {
        let current = [2, 3].map { window(CGWindowID($0)) }
        let ordered = PreviewController.keepingOrder(current, previous: [1, 2, 3])
        #expect(ordered.map(\.id) == [2, 3])
    }
}

struct CaptureValidationTests {
    private func image(width: Int, height: Int) -> CGImage {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!.makeImage()!
    }

    @Test func fullWindowCaptureIsAccepted() {
        #expect(ThumbnailService.matchesAspect(image(width: 1643, height: 977), of: CGRect(x: 0, y: 0, width: 1643, height: 977)))
    }

    @Test func retinaCaptureIsAccepted() {
        #expect(ThumbnailService.matchesAspect(image(width: 2880, height: 1800), of: CGRect(x: 0, y: 0, width: 1440, height: 900)))
    }

    /// cmux 實測：1643×977 的視窗用私有 API 只截到 40×977 的一條
    @Test func partialStripCaptureIsRejected() {
        #expect(!ThumbnailService.matchesAspect(image(width: 40, height: 977), of: CGRect(x: 0, y: 0, width: 1643, height: 977)))
    }
}

struct DockLayoutTests {
    /// 實測：tilesize 28、largesize 75、開啟放大時，名稱標籤頂端距螢幕底 120pt
    @Test func magnifiedExtentPlusLabelMatchesMeasurement() {
        let extent = PanelGeometry.dockItemExtent(tileSize: 28, largeSize: 75, magnification: true)
        #expect(extent + PanelGeometry.dockLabelHeight == 120)
    }

    @Test func panelClearsLabelEvenWhileDockIsSlidingIn() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // 自動隱藏的 Dock 滑出途中：圖示還在螢幕底邊以下
        let slidingIcon = CGRect(x: 900, y: -30, width: 42, height: 42)
        let extent = PanelGeometry.dockItemExtent(tileSize: 28, largeSize: 75, magnification: true)
        let frame = PanelGeometry.panelFrame(
            size: CGSize(width: 400, height: 240), icon: slidingIcon, edge: .bottom, screen: screen,
            dockExtent: extent, labelClearance: PanelGeometry.dockLabelHeight, gap: 6
        )
        #expect(frame.minY == 126)
    }

    @Test func dockBandReachesPanelSoTheGapNeverHidesIt() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 700, y: 126, width: 400, height: 240)
        let band = PanelGeometry.dockBand(panel: panel, edge: .bottom, screen: screen)
        #expect(band.contains(CGPoint(x: 900, y: 100)))
        #expect(band.maxY >= panel.minY)
    }

    /// 通道涵蓋「圖示頂 → 面板底」：Dock 已取消選取、游標還在途中時不收起；但不含圖示列與通道外側
    @Test func corridorCoversPathFromIconToPanelOnly() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let extent = PanelGeometry.dockItemExtent(tileSize: 28, largeSize: 75, magnification: true)  // 94
        let icon = CGRect(x: 880, y: 5, width: 89, height: 89)
        let panel = CGRect(x: 700, y: 126, width: 400, height: 240)
        let corridor = PanelGeometry.corridor(panel: panel, icon: icon, edge: .bottom, screen: screen, dockExtent: extent)
        #expect(corridor.contains(CGPoint(x: 924, y: 110)))   // 名稱標籤區（游標往上途中）
        #expect(corridor.contains(CGPoint(x: 720, y: 120)))   // 斜向移往面板左側
        #expect(corridor.maxY >= panel.minY)
        #expect(!corridor.contains(CGPoint(x: 924, y: 50)))   // 圖示列本身交給 Dock 事件
        #expect(!corridor.contains(CGPoint(x: 300, y: 110)))  // 沿螢幕底往旁邊走
    }

    @Test func corridorOnSideDocksSpansIconToPanel() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 150, y: 400, width: 300, height: 400)
        let left = PanelGeometry.corridor(panel: panel, icon: CGRect(x: 5, y: 560, width: 89, height: 89), edge: .left, screen: screen, dockExtent: 94)
        #expect(left.contains(CGPoint(x: 120, y: 600)))
        #expect(!left.contains(CGPoint(x: 50, y: 600)))
        let rightPanel = CGRect(x: 1470, y: 400, width: 300, height: 400)
        let right = PanelGeometry.corridor(panel: rightPanel, icon: CGRect(x: 1826, y: 560, width: 89, height: 89), edge: .right, screen: screen, dockExtent: 94)
        #expect(right.contains(CGPoint(x: 1800, y: 600)))
        #expect(!right.contains(CGPoint(x: 1870, y: 600)))
    }

    /// 圖示列只涵蓋放大圖示靜止外緣以內；名稱標籤區與更上方不算（Dock 在那裡不發取消選取）
    @Test func dockRowStopsAtMagnifiedIconEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let extent = PanelGeometry.dockItemExtent(tileSize: 28, largeSize: 75, magnification: true)  // 94
        let icon = CGRect(x: 880, y: 5, width: 42, height: 42)  // 放大動畫中、尚未到靜止大小
        let row = PanelGeometry.dockRow(icon: icon, edge: .bottom, screen: screen, dockExtent: extent)
        #expect(row.contains(CGPoint(x: 300, y: 50)))     // 圖示列任何位置
        #expect(!row.contains(CGPoint(x: 300, y: 110)))   // 名稱標籤區
        let corridor = PanelGeometry.corridor(
            panel: CGRect(x: 700, y: 126, width: 400, height: 240), icon: icon, edge: .bottom, screen: screen, dockExtent: extent
        )
        #expect(corridor.minY <= row.maxY)                // 圖示列與通道相接，往上移不會有空隙
        let left = PanelGeometry.dockRow(icon: CGRect(x: 5, y: 500, width: 89, height: 89), edge: .left, screen: screen, dockExtent: 94)
        #expect(left.contains(CGPoint(x: 50, y: 900)) && !left.contains(CGPoint(x: 120, y: 900)))
        let right = PanelGeometry.dockRow(icon: CGRect(x: 1826, y: 500, width: 89, height: 89), edge: .right, screen: screen, dockExtent: 94)
        #expect(right.contains(CGPoint(x: 1870, y: 100)) && !right.contains(CGPoint(x: 1800, y: 100)))
    }

    @Test func nearestScreenPicksDockScreenWhenIconIsOffscreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        #expect(PanelGeometry.nearestScreen(to: CGPoint(x: -1000, y: -20), in: screens) == 1)
    }
}

struct ClosedWindowTests {
    @Test func closedFlagDefaultsToFalseAndAffectsEquality() {
        var window = WindowInfo(id: 1, pid: 1, title: "Main", frame: .zero, isMinimized: false, isOnOtherSpace: false, ax: nil)
        #expect(window.isClosed == false)
        let open = window
        window.isClosed = true
        #expect(open != window)
    }
}
