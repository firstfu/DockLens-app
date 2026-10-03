//
//  OnboardingView.swift
//  DockLens
//
//  首次啟動的權限引導。輔助使用是必要的，授予後 AppCoordinator 立即開始運作；
//  螢幕錄製是選用的（只用來顯示縮圖），使用者可選「先不要」以無縮圖模式使用。兩項都授予後自動關閉。
//

import SwiftUI

struct OnboardingView: View {
    let permissions: Permissions
    /// 使用者選擇不給螢幕錄製、直接以無縮圖模式使用
    let continueWithoutScreenRecording: () -> Void

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
                Text("游標停在 Dock 圖示上，即可預覽該 App 的所有視窗。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                StepCard(
                    symbol: "accessibility",
                    title: "輔助使用",
                    tag: "必要",
                    detail: "偵測游標停在哪個 Dock 圖示、切換與關閉視窗",
                    granted: permissions.accessibility,
                    request: permissions.requestAccessibility
                )
                StepCard(
                    symbol: "rectangle.dashed.badge.record",
                    title: "螢幕錄製",
                    tag: "選用",
                    detail: "顯示視窗縮圖（僅在本機處理，不會上傳、不會錄影）",
                    granted: permissions.screenRecording,
                    request: permissions.requestScreenRecording
                )
            }

            footer
        }
        .padding(32)
        .frame(width: 520)
        .animation(.snappy, value: permissions.accessibility)
    }

    /// 已有輔助使用、還沒有螢幕錄製時，說明無縮圖模式並讓使用者可以先用。
    @ViewBuilder
    private var footer: some View {
        if permissions.accessibility && !permissions.screenRecording {
            VStack(spacing: 10) {
                Text("沒有螢幕錄製也能用：預覽會以 App 圖示和視窗標題顯示，\n一樣可以切換、關閉、縮小視窗。之後可在設定裡開啟縮圖。")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("先不要縮圖，直接使用", action: continueWithoutScreenRecording)
                    .buttonStyle(.glass)
            }
            .transition(.opacity)
        } else {
            Text("授權後即自動生效，不需重新啟動。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StepCard: View {
    let symbol: String
    let title: LocalizedStringKey
    /// 標題旁的小標籤（「必要」／「選用」）
    let tag: LocalizedStringKey
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
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                // 翻譯長度差很多：說明要能換成多行，卡片高度跟著長
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
