//
//  CalendarAgendaTests.swift
//  DockLensTests
//
//  驗證行程區塊的純邏輯：今天／明天的選擇、全天行程排序、行數上限、視訊會議連結偵測。
//

import Foundation
import Testing
@testable import DockLens

struct CalendarAgendaTests {
    /// 固定時區的曆法，讓日界不受執行環境影響
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    /// 2026-10-02 指定時間（台北）
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(eventID: title, title: title, start: start, end: end, isAllDay: allDay,
                    location: nil, color: .fallback, meetingURL: nil)
    }

    @Test func showsTodayRemainingEventsWithAllDayFirst() {
        let events = [
            event("晚餐", at(19), at(20)),
            event("早會", at(9), at(10)),
            event("站會", at(14), at(14, 30)),
            event("生日", at(0), at(0, day: 3), allDay: true),
        ]
        let day = CalendarAgenda.plan(events: events, now: at(13), calendar: calendar)
        #expect(day?.kind == .today)
        // 已結束的早會不列；全天行程排最前
        #expect(day?.events.map(\.title) == ["生日", "站會", "晚餐"])
    }

    @Test func keepsOngoingEvent() {
        let day = CalendarAgenda.plan(events: [event("會議", at(12), at(14))], now: at(13), calendar: calendar)
        #expect(day?.events.map(\.title) == ["會議"])
    }

    @Test func fallsBackToTomorrowWhenTodayIsDone() {
        let events = [event("早會", at(9), at(10)), event("明天看診", at(10, day: 3), at(11, day: 3))]
        let day = CalendarAgenda.plan(events: events, now: at(21), calendar: calendar)
        #expect(day?.kind == .tomorrow)
        #expect(day?.events.map(\.title) == ["明天看診"])
    }

    @Test func returnsNilWhenNothingLeft() {
        #expect(CalendarAgenda.plan(events: [event("早會", at(9), at(10))], now: at(21), calendar: calendar) == nil)
    }

    @Test func capsRowsAndCountsHidden() {
        let events = (0..<9).map { event("e\($0)", at(14 + $0), at(14 + $0, 30)) }
        let day = CalendarAgenda.plan(events: events, now: at(13), calendar: calendar)
        #expect(day?.events.count == CalendarAgenda.maxRows)
        #expect(day?.hiddenCount == 9 - CalendarAgenda.maxRows)
    }

    @Test func detectsMeetingLinks() {
        let zoom = URL(string: "https://us02web.zoom.us/j/123456")!
        #expect(CalendarAgenda.meetingURL(url: zoom, location: nil, notes: nil) == zoom)
        #expect(CalendarAgenda.meetingURL(url: nil, location: "會議室 3F", notes: "加入：https://meet.google.com/abc-defg-hij 謝謝")
            == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(CalendarAgenda.meetingURL(url: nil, location: "https://teams.microsoft.com/l/meetup-join/xyz", notes: nil) != nil)
    }

    @Test func ignoresNonMeetingLinks() {
        #expect(CalendarAgenda.meetingURL(url: URL(string: "https://example.com"), location: "台北 101", notes: "https://docs.google.com/x") == nil)
        // 只比對網域結尾，不能被「含有 zoom.us 字樣」的其他網域騙過
        #expect(CalendarAgenda.meetingURL(url: URL(string: "https://zoom.us.evil.com/j/1"), location: nil, notes: nil) == nil)
    }
}

/// 檢查更新的純邏輯：版本號比較、GitHub release JSON 解析。
struct UpdateCheckerTests {
    @Test(arguments: [("1.0.4", "1.0.3", true), ("1.0.10", "1.0.9", true), ("1.1", "1.0.9", true),
                      ("1.0.3", "1.0.3", false), ("1.0.2", "1.0.3", false), ("1.0", "1.0.0", false)])
    func comparesVersionsNumerically(candidate: String, current: String, newer: Bool) {
        #expect(UpdateChecker.isNewer(candidate, than: current) == newer)
    }

    @Test func parsesReleaseAndStripsV() throws {
        let json = #"{"tag_name":"v1.0.4","html_url":"https://github.com/firstfu/DockLens-app/releases/tag/v1.0.4","name":"x"}"#
        let release = try #require(UpdateChecker.parseRelease(Data(json.utf8)))
        #expect(release.version == "1.0.4")
        #expect(release.url.absoluteString.hasSuffix("/v1.0.4"))
        #expect(UpdateChecker.parseRelease(Data("{}".utf8)) == nil)
    }
}
