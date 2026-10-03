//
//  AgendaView.swift
//  DockLens
//
//  「行事曆」Dock 圖示的行程區塊：今天（或明天）的行程列表，顯示日曆顏色、時間、進行中／倒數，
//  有視訊會議連結的行程附「加入」鈕；點一下行程在行事曆 App 打開。
//  高度只由狀態與行數決定（固定值）：面板大小在顯示時就算好，之後不能被內容撐開。
//

import SwiftUI

struct AgendaView: View {
    static let minWidth: CGFloat = 340
    static let titleHeight: CGFloat = 18
    static let rowHeight: CGFloat = 38
    static let rowSpacing: CGFloat = 2
    static let footerHeight: CGFloat = 16
    /// 權限提示、沒有行程等單一訊息的高度
    static let messageHeight: CGFloat = 52

    let agenda: AgendaModel

    /// 依狀態算出區塊高度（PreviewModel 計算版面上限時使用，必須與 body 實際高度一致）。
    static func height(for status: AgendaStatus) -> CGFloat {
        guard case .day(let day) = status else { return messageHeight }
        let rows = CGFloat(day.events.count)
        return titleHeight + rowSpacing + rows * rowHeight + max(0, rows - 1) * rowSpacing
            + (day.hiddenCount > 0 ? rowSpacing + footerHeight : 0)
    }

    var body: some View {
        Group {
            switch agenda.status {
            case .needsPermission:
                message(symbol: "calendar.badge.exclamationmark", text: "允許讀取行事曆，即可在這裡看到今天的行程") {
                    PillButton(title: "允許", prominent: true, action: agenda.requestAccess)
                        .probe("agenda.allow")
                }
            case .denied:
                message(symbol: "calendar.badge.exclamationmark", text: "未允許讀取行事曆") {
                    PillButton(title: "打開設定", action: agenda.openSettings)
                }
            case .empty:
                message(symbol: "calendar.badge.checkmark", text: "今天和明天都沒有行程") { EmptyView() }
            case .day(let day):
                // 每分鐘更新一次「進行中／幾分鐘後」；只在面板顯示時存在，不影響閒置成本
                TimelineView(.everyMinute) { context in
                    dayView(day, now: context.date)
                }
            }
        }
        .frame(minWidth: Self.minWidth, maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height(for: agenda.status))
    }

    private func dayView(_ day: AgendaDay, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            title(for: day, now: now)
            let dayStart = Self.dayStart(day, now: now)
            ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                AgendaRow(event: event, now: now, dayStart: dayStart, open: { agenda.open(event) }, join: { agenda.join(event) })
                    .probe("agenda.row.\(index)")
            }
            if day.hiddenCount > 0 {
                Text("還有 \(day.hiddenCount) 個行程")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.footerHeight)
                    .padding(.leading, 8)
            }
        }
    }

    /// 介面實際使用的語言（App 有翻譯的語言中最符合使用者偏好者）＋使用者的地區。
    /// 為什麼不用 `Locale.current`：使用者的系統語言若是 App 沒翻譯的語言，介面會退回英文，日期與時間長度卻會照系統語言格式化，混成兩種語言。
    static let uiLocale: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: language) }
        return Locale(identifier: "\(language)_\(region)")
    }()

    /// 顯示中那一天的 00:00
    private static func dayStart(_ day: AgendaDay, now: Date) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return day.kind == .today ? today : Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private func title(for day: AgendaDay, now: Date) -> some View {
        let date = Self.dayStart(day, now: now)
        return HStack(spacing: 6) {
            Text(day.kind == .today ? "今天" : "明天")
                .font(.system(size: 12, weight: .semibold))
            // 用介面語言格式化（而不是系統地區），日期才會和旁邊的「今天／明天」同一種語言
            Text(date.formatted(Date.FormatStyle(locale: Self.uiLocale).month().day().weekday(.abbreviated)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if day.kind == .tomorrow {
                Text("今天已沒有行程")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .frame(height: Self.titleHeight)
        .padding(.leading, 8)
    }

    private func message(symbol: String, text: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 8)
    }
}

/// 單一行程列。整列可點（在行事曆打開）；有會議連結時右側有「加入」鈕。
private struct AgendaRow: View {
    let event: AgendaEvent
    let now: Date
    /// 顯示中那一天的 00:00（判斷跨日行程）
    let dayStart: Date
    let open: () -> Void
    let join: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: 26)
                    timeColumn
                        .frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isPast ? .secondary : .primary)
                        if let detail {
                            Text(detail.text)
                                .font(.system(size: 11, weight: detail.emphasized ? .medium : .regular))
                                .foregroundStyle(detail.emphasized ? AnyShapeStyle(detail.tint) : AnyShapeStyle(.secondary))
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("在行事曆中打開")
            .accessibilityLabel(event.title)

            if event.meetingURL != nil {
                PillButton(title: "加入", symbol: "video.fill", prominent: isOngoingOrSoon, action: join)
                    .help("加入視訊會議")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: AgendaView.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOngoing ? AnyShapeStyle(color.opacity(0.14)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.08 : 0)))
        )
        .onHover { isHovering = $0 }
    }

    private var color: Color {
        Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue)
    }

    private var isOngoing: Bool { !event.isAllDay && event.start <= now && now < event.end }
    private var isPast: Bool { !event.isAllDay && event.end <= now }
    /// 進行中或 10 分鐘內開始：「加入」鈕改為醒目樣式
    private var isOngoingOrSoon: Bool {
        isOngoing || (!event.isAllDay && event.start > now && event.start.timeIntervalSince(now) <= 10 * 60)
    }

    @ViewBuilder
    private var timeColumn: some View {
        if event.isAllDay {
            Text("全天")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                // 時間欄寬度固定，較長的翻譯（例如 Ganztägig）縮小字級塞進去
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(startLabel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                Text(Self.timeFormatter.string(from: event.end))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// 前一天就開始的跨日行程不顯示前一天的時間，改標「跨日」
    private var startLabel: String {
        event.start < dayStart ? String(localized: "跨日", comment: "前一天就開始的行程，時間欄很窄，請盡量短") : Self.timeFormatter.string(from: event.start)
    }

    /// 第二行：進行中／即將開始優先，其次是地點（地點只是會議網址時改寫成「視訊會議」）
    private var detail: (text: String, emphasized: Bool, tint: Color)? {
        if isOngoing {
            let left = Self.duration(event.end.timeIntervalSince(now))
            return (String(localized: "進行中 · 還剩 \(left)", comment: "%@ 為剩餘時間，例如「25 分鐘」"), true, color)
        }
        if !event.isAllDay, event.start > now, event.start.timeIntervalSince(now) <= 60 * 60 {
            let until = Self.duration(event.start.timeIntervalSince(now))
            return (String(localized: "\(until)後開始", comment: "%@ 為距離開始的時間，例如「9 分鐘」"), true, .orange)
        }
        if let location = event.location, !location.contains("://") { return (location, false, .secondary) }
        if event.meetingURL != nil { return (String(localized: "視訊會議"), false, .secondary) }
        return nil
    }

    /// 時間欄固定 24 小時制（20:35）：「下午 8:35」這類 12 小時制字串太寬，塞不進固定寬度的時間欄
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 把秒數寫成介面語言的時間長度，例如「25分鐘」「1小時20分鐘」「1 hr, 20 min」（不足 1 分鐘算 1 分鐘）。
    /// 交給系統格式化：各語言的單位、複數、數字寫法都不同，自己拼字串只會對中文正確。
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AgendaView.uiLocale))
    }
}

/// 行程區塊的膠囊按鈕（允許、打開設定、加入會議）。
private struct PillButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.1))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
