//
//  FixtureApp.swift
//  DockLensFixture
//
//  DockLens 端到端測試專用的假 App：啟動時開 3 個不同顏色、編號的視窗，⌘N 開新視窗。
//  自我測試會對它執行關閉視窗、隱藏、結束等破壞性操作，避免動到使用者真正在用的 App。
//  `--hide-on-close` 模式模擬 Notion、Slack 這類 App：只有一個主視窗，按 X 只是藏起來，
//  點 Dock 圖示（重新打開事件）時再把它叫回來。`--auto-close` 會在啟動 1.5 秒後自動按 X（量測用）。
//

import AppKit

@main
final class FixtureApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var counter = 0
    private let hidesOnClose = CommandLine.arguments.contains("--hide-on-close")

    static func main() {
        let app = NSApplication.shared
        let delegate = FixtureApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if hidesOnClose {
            newWindow(nil)
            windows.first?.title = "Fixture Main"
            if CommandLine.arguments.contains("--auto-close") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.windows.first?.performClose(nil) }
            }
        } else {
            for _ in 0..<3 { newWindow(nil) }
        }
    }

    /// 模擬 Notion：按 X 只把視窗藏起來（ordered out），App 仍保留它。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hidesOnClose else { return true }
        sender.orderOut(nil)
        return false
    }

    /// 重新打開 App（點 Dock 圖示、NSWorkspace 開啟執行中的 App）時，若沒有可見視窗就把主視窗叫回來。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// 關掉最後一個視窗也不結束（模擬一般文件型 App）。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 開一個新視窗，標題為「Fixture N」，尺寸依序循環三種長寬比。
    @objc func newWindow(_ sender: Any?) {
        counter += 1
        let sizes = [NSSize(width: 640, height: 400), NSSize(width: 520, height: 390), NSSize(width: 700, height: 380)]
        let size = sizes[(counter - 1) % sizes.count]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Fixture \(counter)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NumberView(number: counter)
        if let visible = NSScreen.main?.visibleFrame {
            let offset = CGFloat((counter - 1) % 6) * 40
            window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 120 + offset, y: visible.maxY - 80 - offset))
        }
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let fileItem = NSMenuItem()
        fileItem.submenu = NSMenu(title: "File")
        fileItem.submenu?.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(fileItem)
        NSApp.mainMenu = main
    }
}

/// 滿版色塊＋大號編號，讓縮圖一眼就能對應到哪個視窗。
private final class NumberView: NSView {
    private let number: Int

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("不支援 Interface Builder") }

    override func draw(_ dirtyRect: NSRect) {
        let hue = CGFloat((number * 67) % 360) / 360
        NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
        bounds.fill()
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(bounds.height * 0.6, 220), weight: .black),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
