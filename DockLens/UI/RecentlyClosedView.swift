//
//  RecentlyClosedView.swift
//  DockLens
//
//  預覽面板底部的「最近關閉」區塊：這個 App 剛關掉的文件，點一下重新打開。
//  高度只由筆數決定（固定值）：面板大小在顯示時就算好，之後不能被內容撐開（與播放列、行程區塊相同）。
//

import SwiftUI

struct RecentlyClosedView: View {
    static let minWidth: CGFloat = 260
    static let titleHeight: CGFloat = 16
    static let rowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    /// 檔名（含資料夾）最寬多少：沒有視窗卡片撐寬時，面板寬度由這一區決定，超長檔名不能把面板撐到半個螢幕
    static let maxNameWidth: CGFloat = 300

    let entries: [ClosedWindowEntry]
    let restore: (ClosedWindowEntry) -> Void

    /// 區塊總高度（PreviewModel 計算直排版面上限時使用，必須與 body 實際高度一致）。
    static func height(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return titleHeight + rowSpacing + CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            Text("最近關閉")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: Self.titleHeight)
                .padding(.leading, 8)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                RecentlyClosedRow(entry: entry) { restore(entry) }
                    .probe("closed.\(index)")
            }
        }
        .frame(minWidth: Self.minWidth, maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height(count: entries.count))
    }
}

/// 一筆最近關閉的文件：檔案圖示＋名稱（淡色接上所在資料夾）＋多久前關的。
private struct RecentlyClosedRow: View {
    let entry: ClosedWindowEntry
    let action: () -> Void
    @State private var isHovering = false

    /// 檔名（深色）接上所在資料夾（淡色）。
    private var label: AttributedString {
        var name = AttributedString(entry.displayName)
        name.font = .system(size: 12, weight: .medium)
        guard !entry.parentName.isEmpty else { return name }
        var parent = AttributedString("  \(entry.parentName)")
        parent.font = .system(size: 11)
        parent.foregroundColor = .secondary
        return name + parent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            // 名稱與資料夾放同一個 Text：太長時整段一起從中間截斷，不會只剩資料夾
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: RecentlyClosedView.maxNameWidth, alignment: .leading)
            Spacer(minLength: 12)
            Text(entry.closedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // 跟著介面實際使用的語言（見 AgendaView.uiLocale），不要用系統語言
                .environment(\.locale, AgendaView.uiLocale)
        }
        .padding(.horizontal, 8)
        .frame(height: RecentlyClosedView.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(isHovering ? 0.10 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: action)
        .help(entry.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(String(localized: "點擊重新打開"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
