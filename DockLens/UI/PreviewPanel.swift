//
//  PreviewPanel.swift
//  DockLens
//
//  承載預覽 UI 的浮動面板。
//  - nonactivatingPanel：點擊面板不會搶走前景 App 的焦點（和系統 Dock 行為一致）
//  - popUpMenu 層級：浮在 Dock（kCGDockWindowLevel）之上
//  - 所有桌面、全螢幕 App 上都能顯示
//

import AppKit
import SwiftUI

final class PreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        // 面板不會成為 key window，預設收不到滑鼠移動事件；開啟後內容 view 的追蹤區才能即時得知游標在哪張卡片上
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 面板內容 view：第一下點擊就生效（不需先「啟用」視窗），並以 activeAlways 追蹤區自行追蹤游標。
/// 為什麼自己追蹤：面板永遠不是 key window、App 也不會成為前景，SwiftUI 內建的 `onHover` 在這種視窗裡
/// 時有時無（實測游標停在卡片正中央卻沒觸發），滑過卡片就不會浮現紅黃綠按鈕。
final class PanelHostingView: NSHostingView<AnyView> {
    var onMouseInside: ((Bool) -> Void)?
    /// 游標進出面板（啟停滑過輪詢保險用）
    var onMouseInsideChanged: ((Bool) -> Void)?
    /// 游標在面板內移動時回報位置（面板內容座標，左上為原點）；離開面板時回報 nil
    var onMouseMoved: ((CGPoint?) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseInside?(true)
        onMouseInsideChanged?(true)
        onMouseMoved?(contentPoint(event))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(contentPoint(event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseInside?(false)
        onMouseInsideChanged?(false)
        onMouseMoved?(nil)
    }

    /// 事件位置轉成面板內容座標（左上為原點，與 SwiftUI 座標空間一致）。
    private func contentPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    /// 以目前游標位置重新計算（面板內容替換後呼叫，讓游標下的卡片立即呈現滑過狀態）。
    func reportCurrentMouseLocation() {
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(inWindow, from: nil)
        guard bounds.contains(point) else { onMouseMoved?(nil); return }
        onMouseMoved?(isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y))
    }
}
