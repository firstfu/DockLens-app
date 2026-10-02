//
//  SettingsView.swift
//  DockLens
//
//  設定視窗：外觀、行為、權限狀態、關於。
//

import SwiftUI

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        @Bindable var settings = coordinator.settings
        Form {
            Section("一般") {
                Toggle("啟用視窗預覽", isOn: $settings.isEnabled)
                Toggle("登入時自動啟動", isOn: $settings.launchAtLogin)
            }
            Section("外觀") {
                LabeledContent("縮圖高度") {
                    HStack {
                        Slider(value: $settings.thumbnailHeight, in: 90...280, step: 10)
                        Text("\(Int(settings.thumbnailHeight)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle("顯示視窗標題", isOn: $settings.showsTitles)
            }
            Section("行為") {
                LabeledContent("顯示延遲") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...0.8, step: 0.02)
                        Text("\(Int(settings.hoverDelay * 1000)) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle("包含其他桌面（Space）的視窗", isOn: $settings.includesOtherSpaces)
                Toggle("顯示按 X 關掉的視窗（點擊重新打開）", isOn: $settings.showsClosedWindows)
                Toggle("App 沒有視窗時仍顯示面板", isOn: $settings.showsEmptyState)
                Toggle("滑過「行事曆」時顯示今天的行程", isOn: $settings.showsCalendarAgenda)
            }
            Section("權限") {
                PermissionRow(title: "輔助使用", granted: coordinator.permissions.accessibility) {
                    coordinator.permissions.requestAccessibility()
                }
                PermissionRow(title: "螢幕錄製", granted: coordinator.permissions.screenRecording) {
                    coordinator.permissions.requestScreenRecording()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { coordinator.permissions.refresh() }
    }
}

/// 權限狀態列：已授權顯示綠勾，未授權顯示前往按鈕。
struct PermissionRow: View {
    let title: LocalizedStringKey
    let granted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent(title) {
            if granted {
                Label("已授權", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("前往授權", action: request)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
