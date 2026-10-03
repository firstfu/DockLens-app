//
//  NoScreenRecordingTests.swift
//  DockLensTests
//
//  驗證無縮圖模式（沒有螢幕錄製權限）：啟動時何時要跳權限引導、長條卡片的尺寸與版面計算。
//

import AppKit
import Testing
@testable import DockLens

struct NoScreenRecordingTests {
    @Test(arguments: [
        // (輔助使用, 螢幕錄製, 已選擇不給螢幕錄製, 是否要顯示引導)
        (false, false, false, true),
        (false, true, false, true),
        (false, false, true, true),   // 缺必要權限：表態過也要顯示
        (true, false, false, true),   // 缺選用權限、還沒表態：詢問一次
        (true, false, true, false),   // 已選擇無縮圖模式：不再打擾
        (true, true, false, false),
    ])
    func onboardingOnlyWhenNeeded(accessibility: Bool, screenRecording: Bool, declined: Bool, expected: Bool) {
        #expect(AppCoordinator.needsOnboarding(
            accessibility: accessibility, screenRecording: screenRecording, declinedScreenRecording: declined
        ) == expected)
    }

    @Test(arguments: [(150.0, 240.0, 68.0), (90.0, 144.0, 56.0), (280.0, 448.0, 126.0)])
    func listCardScalesWithThumbnailHeight(height: Double, expectedWidth: Double, expectedHeight: Double) {
        let size = PanelGeometry.listCardSize(thumbnailHeight: height)
        #expect(Double(size.width) == expectedWidth)
        #expect(Double(size.height) == expectedHeight)
    }

    @MainActor
    @Test func listModeIgnoresThumbnailsAndAspect() {
        let windows = [
            WindowInfo(id: 1, pid: 1, title: "寬", frame: CGRect(x: 0, y: 0, width: 1600, height: 500),
                       isMinimized: false, isOnOtherSpace: false, ax: nil),
            WindowInfo(id: 2, pid: 1, title: "直", frame: CGRect(x: 0, y: 0, width: 400, height: 900),
                       isMinimized: true, isOnOtherSpace: false, ax: nil),
        ]
        let image = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let model = PreviewModel(
            app: nil, windows: windows, thumbnail: { _ in image },
            thumbnailHeight: 150, showsTitles: true, showsThumbnails: false,
            edge: .bottom, screenSize: CGSize(width: 1920, height: 1080)
        )
        let expected = PanelGeometry.listCardSize(thumbnailHeight: 150)
        #expect(model.cards.allSatisfy { $0.thumbnailSize == expected })
        // 快取裡就算有舊縮圖也不顯示，標題已在卡片內，不另外顯示標題列
        #expect(model.cards.allSatisfy { $0.thumbnail == nil })
        #expect(!model.showsTitles)
    }

    @MainActor
    @Test func listModeColumnsUseListCardHeight() {
        let windows = (1...30).map { index in
            WindowInfo(id: CGWindowID(index), pid: 1, title: "視窗 \(index)", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                       isMinimized: false, isOnOtherSpace: false, ax: nil)
        }
        let screen = CGSize(width: 1920, height: 1080)
        let list = PreviewModel(app: nil, windows: windows, thumbnail: { _ in nil }, thumbnailHeight: 150,
                                showsTitles: true, showsThumbnails: false, edge: .left, screenSize: screen)
        let thumbs = PreviewModel(app: nil, windows: windows, thumbnail: { _ in nil }, thumbnailHeight: 150,
                                  showsTitles: true, showsThumbnails: true, edge: .left, screenSize: screen)
        // 長條卡片比縮圖卡片矮，側邊 Dock 時每欄放得下更多張
        #expect(list.groups[0].count > thumbs.groups[0].count)
    }
}
