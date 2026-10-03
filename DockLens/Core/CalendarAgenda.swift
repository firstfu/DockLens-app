//
//  CalendarAgenda.swift
//  DockLens
//
//  游標停在「行事曆」Dock 圖示上時顯示的行程：以 EventKit 讀取今天（今天已無行程時改為明天）的行程，
//  並從行程的網址／地點／備註找出視訊會議連結，讓面板上可以一鍵加入。
//  為什麼不在游標停上時就詢問權限：游標只是經過就跳出系統對話框很干擾，
//  所以顯示前只「讀取」授權狀態，使用者在面板上按「允許」才詢問（與播放列的做法一致）。
//  只在面板建立時查詢一次，面板顯示期間由 EKEventStoreChanged 通知觸發更新，不輪詢。
//

import AppKit
import EventKit
import os

/// 單一行程（從 EKEvent 複製出需要的欄位，可跨執行緒傳遞）。
nonisolated struct AgendaEvent: Sendable, Equatable, Identifiable {
    /// EKEvent 的 calendarItemIdentifier（同一個週期性行程的每次發生共用；與開始時間組合才唯一）
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    /// 所屬行事曆的顏色（sRGB 0...1）
    let color: AgendaColor
    /// 偵測到的視訊會議連結
    let meetingURL: URL?

    var id: String { "\(eventID)@\(start.timeIntervalSince1970)" }
}

/// 可跨執行緒傳遞的顏色。
nonisolated struct AgendaColor: Sendable, Equatable {
    let red: Double, green: Double, blue: Double
    static let fallback = AgendaColor(red: 0.2, green: 0.5, blue: 1)
}

/// 面板要顯示的那一天。
nonisolated struct AgendaDay: Sendable, Equatable {
    enum Kind: Sendable { case today, tomorrow }
    let kind: Kind
    /// 要顯示的行程（全天行程在前，其餘依開始時間）
    let events: [AgendaEvent]
    /// 超過顯示上限而省略的行程數
    let hiddenCount: Int
}

/// 行程區塊要呈現的狀態。
nonisolated enum AgendaStatus: Sendable, Equatable {
    /// 尚未授權；按下按鈕時才詢問使用者
    case needsPermission
    /// 使用者拒絕（或系統限制）
    case denied
    /// 今天與明天都沒有剩下的行程
    case empty
    case day(AgendaDay)
}

nonisolated enum CalendarAgenda {
    /// 支援顯示行程的 App（系統「行事曆」）
    static let calendarBundleID = "com.apple.iCal"
    /// 面板上最多列出幾個行程（面板大小在顯示時就固定，行數要有上限）
    static let maxRows = 6

    private static let log = Logger(subsystem: "com.firstfu.DockLens", category: "calendar")

    /// EKEventStore 建立成本高（會連線 calaccessd），整個 App 共用一個；
    /// 剛授權時舊的 store 看不到行事曆，所以授權後要換新的。
    /// EKEventStore 官方說明為執行緒安全，因此標為 unchecked。
    private final class StoreBox: @unchecked Sendable {
        private let lock = NSLock()
        private var store: EKEventStore?
        func get() -> EKEventStore {
            lock.withLock {
                if let store { return store }
                let created = EKEventStore()
                store = created
                return created
            }
        }
        func reset() { lock.withLock { store = nil } }
    }
    private static let box = StoreBox()

    /// 讀取要顯示的行程；尚未授權時不會跳出詢問。在背景執行緒呼叫（EventKit 查詢是同步的）。
    /// - Parameter now: 目前時間（測試可注入）
    /// - Returns: 行程區塊狀態
    static func status(now: Date = .now) -> AgendaStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: break
        case .notDetermined: return .needsPermission
        // writeOnly 讀不到行程，視同拒絕：只能請使用者到系統設定改成完整取用
        default: return .denied
        }
        let store = box.get()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return .empty }
        let predicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        let events = store.events(matching: predicate).map(makeEvent)
        log.notice("讀取行程：\(events.count) 個")
        return plan(events: events, now: now, calendar: calendar).map(AgendaStatus.day) ?? .empty
    }

    /// 詢問使用者是否允許讀取行事曆，回傳詢問後的最新狀態。
    static func requestAccess() async -> AgendaStatus {
        do {
            let granted = try await box.get().requestFullAccessToEvents()
            log.notice("行事曆授權結果：\(granted)")
        } catch {
            log.error("行事曆授權失敗：\(error.localizedDescription, privacy: .public)")
        }
        box.reset()
        return await Task.detached(priority: .userInitiated) { status() }.value
    }

    /// 在「行事曆」App 打開該行程。`ical://ekevent/` 是行事曆 App 自己註冊的網址格式（非公開文件），
    /// 打不開時退回只打開行事曆 App。
    @MainActor
    static func open(_ event: AgendaEvent) {
        let id = event.eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.eventID
        if let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        openCalendarApp()
    }

    /// 打開「行事曆」App（未執行時會啟動它）。
    @MainActor
    static func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: calendarBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 打開「系統設定 › 隱私權與安全性 › 行事曆」。
    @MainActor
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 純邏輯（可測試）

    /// 決定要顯示哪一天：今天還有沒結束的行程就顯示今天，否則顯示明天。
    /// 今天的全天行程只要日期涵蓋今天就算「還沒結束」。
    /// - Parameters:
    ///   - events: 今天 00:00 到後天 00:00 之間的所有行程
    ///   - now: 目前時間
    ///   - calendar: 用來切日界的曆法
    /// - Returns: 要顯示的那一天；今明兩天都沒有則為 nil
    static func plan(events: [AgendaEvent], now: Date, calendar: Calendar) -> AgendaDay? {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow) else { return nil }

        let today = events.filter { $0.end > now && $0.start < startOfTomorrow }
        if let day = makeDay(.today, today) { return day }
        let tomorrow = events.filter { $0.end > startOfTomorrow && $0.start < endOfTomorrow }
        return makeDay(.tomorrow, tomorrow)
    }

    private static func makeDay(_ kind: AgendaDay.Kind, _ events: [AgendaEvent]) -> AgendaDay? {
        guard !events.isEmpty else { return nil }
        let sorted = events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start != rhs.start ? lhs.start < rhs.start : lhs.title < rhs.title
        }
        return AgendaDay(kind: kind, events: Array(sorted.prefix(maxRows)), hiddenCount: max(0, sorted.count - maxRows))
    }

    /// 已知的視訊會議服務網域（含子網域）。
    private static let meetingHosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "meet.jit.si", "chime.aws", "gotomeeting.com", "around.co",
    ]

    /// 依序從網址欄、地點、備註找出第一個視訊會議連結。
    /// - Returns: 會議連結；都沒有則為 nil
    static func meetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeetingURL(url) { return url }
        for text in [location, notes].compactMap({ $0 }) where !text.isEmpty {
            if let found = links(in: text).first(where: isMeetingURL) { return found }
        }
        return nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    private static func makeEvent(_ event: EKEvent) -> AgendaEvent {
        let color = event.calendar?.color?.usingColorSpace(.sRGB).map {
            AgendaColor(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent)
        } ?? .fallback
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgendaEvent(
            eventID: event.calendarItemIdentifier,
            title: (event.title?.isEmpty == false ? event.title : nil) ?? String(localized: "（無標題）", comment: "沒有標題的行事曆行程"),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: location?.isEmpty == false ? location : nil,
            color: color,
            meetingURL: meetingURL(url: event.url, location: event.location, notes: event.notes)
        )
    }
}
