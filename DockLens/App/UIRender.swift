//
//  UIRender.swift
//  DockLens
//
//  翻譯排版檢查（僅 Debug）：`--render-ui <輸出資料夾>` 把引導視窗、設定、預覽面板（縮圖／無縮圖）、
//  播放列、行程區塊用假資料畫成 PNG，畫完即結束。搭配 `-AppleLanguages "(de)"` 逐一語言執行，
//  幾秒就能檢查翻譯有沒有截字或撐破版面，不必每種語言都跑一次要動游標的端到端測試。
//

#if DEBUG
import AppKit
import SwiftUI

enum UIRender {
    /// 輸出資料夾；沒帶 `--render-ui` 時為 nil
    static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--render-ui"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// 依序畫出各畫面並存檔，完成後結束 App。
    /// - Parameter coordinator: 提供設定頁與引導視窗需要的狀態
    static func run(coordinator: AppCoordinator, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pages: [(String, AnyView)] = [
            ("onboarding", AnyView(OnboardingView(permissions: coordinator.permissions, continueWithoutScreenRecording: {}))),
            ("panel-thumbnails", AnyView(PreviewView(model: .sample()))),
            ("panel-side", AnyView(PreviewView(model: .sample(edge: .left)))),
            ("panel-list", AnyView(PreviewView(model: .sample(showsThumbnails: false)))),
            ("panel-list-side", AnyView(PreviewView(model: .sample(edge: .left, showsThumbnails: false)))),
            ("panel-closed", AnyView(PreviewView(model: .sampleClosed()))),
            ("panel-recently-closed", AnyView(PreviewView(model: .sampleRecentlyClosed()))),
            ("panel-recently-closed-side", AnyView(PreviewView(model: .sampleRecentlyClosed(edge: .left)))),
            ("panel-recently-closed-only", AnyView(PreviewView(model: .sampleRecentlyClosed(openWindows: 0)))),
            ("media", AnyView(mediaBars)),
            ("agenda", AnyView(agendas)),
        ]
        for (name, view) in pages {
            await render(view, to: directory.appending(path: "\(name).png"))
        }
        for pane in SettingsPane.allCases {
            await renderSettings(coordinator: coordinator, pane: pane, to: directory.appending(path: "settings-\(pane).png"))
        }
        NSApp.terminate(nil)
    }

    /// 設定頁要放進有標題列的一般視窗才畫得準：側邊欄（NavigationSplitView）在無邊框、經 scaleEffect 放大的
    /// 視窗裡會無視欄寬設定，縮成最窄，看到的截字不代表實際畫面。因此照真正設定視窗的樣式、以原尺寸擷取。
    /// - Parameters:
    ///   - coordinator: 設定頁的資料來源
    ///   - pane: 要畫的分頁
    ///   - url: PNG 輸出位置
    private static func renderSettings(coordinator: AppCoordinator, pane: SettingsPane, to url: URL) async {
        let hosting = NSHostingController(rootView: SettingsView(coordinator: coordinator, initialPane: pane))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .floating
        // NSHostingController 不會把 navigationTitle 帶到視窗（實際的 Settings 場景會），這裡手動補上
        window.title = String(localized: pane.title)
        window.center()
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        let id = CGWindowID(window.windowNumber)
        let image = ScreenCaptureKitFallback().capture(id, maxPixelWidth: 8000) ?? SkyLight.captureWindow(id)
        if let image {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }

    /// 放進實體視窗（Liquid Glass 要經 WindowServer 合成才畫得出來），等一下再擷取。
    /// 輸出 2x 高解析：這台機器若只有 1x 螢幕，就把整個畫面放大 2 倍再擷取（文字與玻璃都是向量，放大後依然銳利），
    /// README 與說明文件放大看才不會糊。
    private static func render(_ view: AnyView, to url: URL) async {
        let content = view
            .padding(32)
            .background(LinearGradient(colors: [Color(red: 0.27, green: 0.26, blue: 0.62), Color(red: 0.12, green: 0.55, blue: 0.68)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
        let size = NSHostingView(rootView: content).fittingSize
        let scale: CGFloat = 2
        let scaled = content.fixedSize().scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        let hosting = NSHostingView(rootView: scaled)
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let frame = NSRect(x: screen.frame.minX + 40, y: screen.frame.minY + 40, width: size.width * scale, height: size.height * scale)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.level = .floating
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        let id = CGWindowID(window.windowNumber)
        let image = ScreenCaptureKitFallback().capture(id, maxPixelWidth: 8000) ?? SkyLight.captureWindow(id)
        if let image {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }

    /// 播放列：Spotify 播放中、音樂暫停（曲名皆為虛構）。
    private static var mediaBars: some View {
        let playing = MediaBarModel(player: .spotify)
        playing.status = .track(NowPlaying(title: "Blue Hour", artist: "The Example Band", isPlaying: true))
        let paused = MediaBarModel(player: .music)
        paused.status = .track(NowPlaying(title: "Morning Light", artist: "Sample Artist", isPlaying: false))
        return VStack(alignment: .leading, spacing: 12) {
            MediaBarView(media: playing)
            MediaBarView(media: paused)
        }
        .frame(width: 340)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// 行事曆行程（虛構）：全天、進行中＋會議、即將開始＋會議、一般行程，並顯示「還有 N 個行程」。
    private static var agendas: some View {
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, meeting: Bool = false, location: String? = nil) -> AgendaEvent {
            AgendaEvent(eventID: title, title: title, start: start, end: end, isAllDay: allDay, location: location,
                        color: .fallback, meetingURL: meeting ? URL(string: "https://zoom.us/j/1") : nil)
        }
        let events = [
            event("Product launch", today, today.addingTimeInterval(86_400), allDay: true),
            event("Design review", now.addingTimeInterval(-900), now.addingTimeInterval(2_700), meeting: true),
            event("1:1 with Sam", now.addingTimeInterval(540), now.addingTimeInterval(2_340), meeting: true),
            event("Lunch", now.addingTimeInterval(7_200), now.addingTimeInterval(10_800), location: "Cafe Nord"),
        ]
        return AgendaView(agenda: AgendaModel(status: .day(AgendaDay(kind: .today, events: events, hiddenCount: 2))))
            .frame(width: AgendaView.minWidth)
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
#endif
