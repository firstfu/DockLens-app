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
            ("settings", AnyView(SettingsView(coordinator: coordinator))),
            ("panel-thumbnails", AnyView(PreviewView(model: .sample()))),
            ("panel-list", AnyView(PreviewView(model: .sample(showsThumbnails: false)))),
            ("panel-list-side", AnyView(PreviewView(model: .sample(edge: .left, showsThumbnails: false)))),
            ("media", AnyView(mediaBars)),
            ("agenda", AnyView(agendas)),
        ]
        for (name, view) in pages {
            await render(view, to: directory.appending(path: "\(name).png"))
        }
        NSApp.terminate(nil)
    }

    /// 放進實體視窗（Liquid Glass 要經 WindowServer 合成才畫得出來），等一下再用 WindowServer 擷取。
    private static func render(_ view: AnyView, to url: URL) async {
        let hosting = NSHostingView(rootView: view
            .padding(24)
            .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)))
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.level = .floating
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500))
        if let image = SkyLight.captureWindow(CGWindowID(window.windowNumber)) {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }

    /// 播放列的兩種最長文字：未授權、被拒（含系統設定路徑）。
    private static var mediaBars: some View {
        let needsPermission = MediaBarModel(player: .music)
        needsPermission.status = .needsPermission
        let denied = MediaBarModel(player: .spotify)
        denied.status = .denied
        return VStack(alignment: .leading, spacing: 12) {
            MediaBarView(media: needsPermission)
            MediaBarView(media: denied)
        }
        .frame(width: 320)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// 行程區塊：今天（全天、進行中＋會議、即將開始、跨日、省略數）、明天、未授權。
    private static var agendas: some View {
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, meeting: Bool = false, location: String? = nil) -> AgendaEvent {
            AgendaEvent(eventID: title, title: title, start: start, end: end, isAllDay: allDay, location: location,
                        color: .fallback, meetingURL: meeting ? URL(string: "https://zoom.us/j/1") : nil)
        }
        let todayEvents = [
            event("Holiday", today, today.addingTimeInterval(86_400), allDay: true),
            event("Overnight build", today.addingTimeInterval(-3_600), now.addingTimeInterval(1_500)),
            event("Design review", now.addingTimeInterval(-600), now.addingTimeInterval(4_800), meeting: true),
            event("1:1", now.addingTimeInterval(540), now.addingTimeInterval(2_340), meeting: true),
        ]
        let tomorrow = today.addingTimeInterval(86_400)
        let tomorrowEvents = [event("Standup", tomorrow.addingTimeInterval(9 * 3_600), tomorrow.addingTimeInterval(9.5 * 3_600), location: "Room 4")]
        return VStack(alignment: .leading, spacing: 12) {
            AgendaView(agenda: AgendaModel(status: .day(AgendaDay(kind: .today, events: todayEvents, hiddenCount: 3))))
            AgendaView(agenda: AgendaModel(status: .day(AgendaDay(kind: .tomorrow, events: tomorrowEvents, hiddenCount: 1))))
            AgendaView(agenda: AgendaModel(status: .needsPermission))
            AgendaView(agenda: AgendaModel(status: .denied))
        }
        .frame(width: AgendaView.minWidth)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
#endif
