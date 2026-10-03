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
                            // 單位長度因語言而異（ms／毫秒／миллисекунд），用最小寬度＋不換行，不要固定寬度
                            .lineLimit(1)
                            .frame(minWidth: 52, alignment: .trailing)
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
                            // 單位長度因語言而異（ms／毫秒／миллисекунд），用最小寬度＋不換行，不要固定寬度
                            .lineLimit(1)
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                }
                Toggle("包含其他桌面（Space）的視窗", isOn: $settings.includesOtherSpaces)
                Toggle("顯示按 X 關掉的視窗（點擊重新打開）", isOn: $settings.showsClosedWindows)
                Toggle("App 沒有視窗時仍顯示面板", isOn: $settings.showsEmptyState)
                Toggle("滑過「行事曆」時顯示今天的行程", isOn: $settings.showsCalendarAgenda)
                Toggle(isOn: $settings.panelShortcuts) {
                    Text("游標在預覽上時的單鍵快捷鍵")
                    Text("W 關閉視窗、M 縮小或還原、H 隱藏 App、Q 結束 App")
                }
            }
            Section("更新") {
                LabeledContent("目前版本", value: coordinator.updates.currentVersion)
                LabeledContent("最新版本") {
                    UpdateStatusView(updates: coordinator.updates)
                }
                Toggle("每週自動檢查更新", isOn: $settings.autoChecksForUpdates)
                    .onChange(of: settings.autoChecksForUpdates) { coordinator.updates.applyAutoCheckSetting() }
                Text("只在按「檢查更新」或開啟自動檢查時連到 GitHub 讀取最新版本號，不送出任何資料。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("權限") {
                PermissionRow(title: "輔助使用", granted: coordinator.permissions.accessibility) {
                    coordinator.permissions.requestAccessibility()
                }
                PermissionRow(title: "螢幕錄製（縮圖，選用）", granted: coordinator.permissions.screenRecording) {
                    coordinator.permissions.requestScreenRecording()
                }
                if !coordinator.permissions.screenRecording {
                    Text("目前以無縮圖模式運作：預覽顯示 App 圖示和視窗標題，切換、關閉、縮小照常可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { coordinator.permissions.refresh() }
    }
}

/// 檢查更新的結果與按鈕。
private struct UpdateStatusView: View {
    let updates: UpdateChecker

    var body: some View {
        HStack(spacing: 8) {
            switch updates.status {
            case .idle: EmptyView()
            case .checking: ProgressView().controlSize(.small)
            case .upToDate: Label("已是最新版本", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Label("無法連線到 GitHub", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .available(let version, _):
                Text("\(version) 可下載").foregroundStyle(.secondary)
                Button("下載") { updates.openDownloadPage() }
                    .buttonStyle(.glassProminent)
            }
            if case .available = updates.status {} else {
                Button("檢查更新") { Task { await updates.check() } }
                    .disabled(updates.status == .checking)
            }
        }
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
