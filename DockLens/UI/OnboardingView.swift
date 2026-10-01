//
//  OnboardingView.swift
//  DockLens
//
//  首次啟動的權限引導。兩項權限都授予後 AppCoordinator 會自動開始運作並關閉此視窗。
//

import SwiftUI

struct OnboardingView: View {
    let permissions: Permissions

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 88, height: 88)
                .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .rect(cornerRadius: 22))

            VStack(spacing: 6) {
                Text("歡迎使用 DockLens")
                    .font(.title.bold())
                Text("游標停在 Dock 圖示上，即可預覽該 App 的所有視窗。\n需要以下兩項權限才能運作：")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                StepCard(
                    symbol: "accessibility",
                    title: "輔助使用",
                    detail: "偵測游標停在哪個 Dock 圖示、切換與關閉視窗",
                    granted: permissions.accessibility,
                    request: permissions.requestAccessibility
                )
                StepCard(
                    symbol: "rectangle.dashed.badge.record",
                    title: "螢幕錄製",
                    detail: "擷取視窗縮圖（僅在本機處理，不會上傳）",
                    granted: permissions.screenRecording,
                    request: permissions.requestScreenRecording
                )
            }

            Text("授權後即自動生效，不需重新啟動。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 520)
    }
}

private struct StepCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(granted ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("授權", action: request)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.snappy, value: granted)
    }
}
