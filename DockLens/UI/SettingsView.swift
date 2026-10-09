//
//  SettingsView.swift
//  DockLens
//
//  設定視窗：仿 macOS 26「系統設定」的側邊欄＋分組表單（與 Liftoff 同一套版型），
//  分頁為一般、外觀、行為、最近關閉、權限。
//  分頁名稱全部沿用既有的 section 標題 key，34 種語言的翻譯不必重做。
//

import SwiftUI

/// 設定視窗的分頁；順序即側邊欄順序。
enum SettingsPane: CaseIterable, Identifiable {
    case general, appearance, behavior, recentlyClosed, permissions

    var id: Self { self }

    /// 用 `LocalizedStringResource` 而非 `LocalizedStringKey`：`UIRender` 要在 SwiftUI 之外轉成視窗標題字串
    var title: LocalizedStringResource {
        switch self {
        case .general: "一般"
        case .appearance: "外觀"
        case .behavior: "行為"
        case .recentlyClosed: "最近關閉"
        case .permissions: "權限"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .behavior: "cursorarrow.rays"
        case .recentlyClosed: "arrow.uturn.backward"
        case .permissions: "hand.raised.fill"
        }
    }

    /// 圖示底色：仿「系統設定」每個項目一個顏色，掃一眼就能分辨
    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .pink
        case .behavior: .blue
        case .recentlyClosed: .orange
        case .permissions: .indigo
        }
    }
}

/// 側邊欄的圖示：彩色圓角方塊＋白色符號，與 macOS「系統設定」同款。
private struct SettingsIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.54, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var selection: SettingsPane

    /// - Parameter initialPane: 一開始顯示的分頁（`UIRender` 逐頁截圖用；一般開啟都從「一般」開始）
    init(coordinator: AppCoordinator, initialPane: SettingsPane = .general) {
        self.coordinator = coordinator
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        // 不用 NavigationSplitView：它在固定大小的視窗裡會無視 navigationSplitViewColumnWidth，側邊欄縮到約 144pt，
        // 德、俄、芬蘭文的分頁名稱被截斷。改成固定寬度的 sidebar 樣式 List，外觀相同、寬度可控
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIconTile(symbol: pane.symbol, tint: pane.tint)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .frame(width: 210)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Settings 場景會把 navigationTitle 設成視窗標題（仿系統設定：標題列顯示目前分頁）
        .navigationTitle(Text(selection.title))
        // 固定大小：切換分頁時視窗不跟著內容忽大忽小（德、俄文等長翻譯以 740 寬驗過不截字）
        .frame(width: 740, height: 520)
        .onAppear { coordinator.permissions.refresh() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettings(coordinator: coordinator, settings: coordinator.settings)
        case .appearance: AppearanceSettings(settings: coordinator.settings)
        case .behavior: BehaviorSettings(settings: coordinator.settings)
        case .recentlyClosed: RecentlyClosedSettings(coordinator: coordinator, settings: coordinator.settings)
        case .permissions: PermissionSettings(permissions: coordinator.permissions)
        }
    }
}

// MARK: - 一般

private struct GeneralSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                AboutHeader(version: coordinator.updates.currentVersion)
            }
            Section {
                Toggle("啟用視窗預覽", isOn: $settings.isEnabled)
                Toggle("登入時自動啟動", isOn: $settings.launchAtLogin)
            }
            Section("更新") {
                LabeledContent("目前版本", value: coordinator.updates.currentVersion)
                LabeledContent("最新版本") {
                    UpdateStatusView(updates: coordinator.updates)
                }
                Toggle("每週自動檢查更新", isOn: $settings.autoChecksForUpdates)
                    .onChange(of: settings.autoChecksForUpdates) { coordinator.updates.applyAutoCheckSetting() }
                Text("只在按「檢查更新」或開啟自動檢查時連到 GitHub 讀取最新版本號，不送出任何資料。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 一般頁最上方的 App 識別卡：圖示＋名稱＋版本（仿系統設定頂端的帳號卡）。
private struct AboutHeader: View {
    let version: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "DockLens").font(.title3.bold())
                Text(verbatim: version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
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

// MARK: - 外觀

private struct AppearanceSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("縮圖高度") {
                    ValueSlider(value: $settings.thumbnailHeight, range: 90...280, step: 10) { Text("\(Int($0)) pt") }
                }
                Toggle("顯示視窗標題", isOn: $settings.showsTitles)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 行為

private struct BehaviorSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("顯示延遲") {
                    ValueSlider(value: $settings.hoverDelay, range: 0...0.8, step: 0.02) { Text("\(Int($0 * 1000)) ms") }
                }
                Toggle(isOn: $settings.panelShortcuts) {
                    Text("游標在預覽上時的單鍵快捷鍵")
                    Text("W 關閉視窗、M 縮小或還原、H 隱藏 App、Q 結束 App")
                }
            }
            Section {
                Toggle("包含其他桌面（Space）的視窗", isOn: $settings.includesOtherSpaces)
                Toggle("App 沒有視窗時仍顯示面板", isOn: $settings.showsEmptyState)
                Toggle("滑過「行事曆」時顯示今天的行程", isOn: $settings.showsCalendarAgenda)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 最近關閉

private struct RecentlyClosedSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.remembersClosedWindows) {
                    Text("記住最近關閉的文件視窗")
                    Text("在該 App 的預覽上一鍵重開。只存在記憶體，結束 DockLens 就清空。")
                }
                .onChange(of: settings.remembersClosedWindows) { coordinator.applyClosedWindowSetting() }
                Toggle("顯示按 X 關掉的視窗（點擊重新打開）", isOn: $settings.showsClosedWindows)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 權限

private struct PermissionSettings: View {
    let permissions: Permissions

    var body: some View {
        Form {
            Section {
                PermissionRow(title: "輔助使用", symbol: "accessibility", granted: permissions.accessibility) {
                    permissions.requestAccessibility()
                }
                PermissionRow(title: "螢幕錄製（縮圖，選用）", symbol: "rectangle.dashed.badge.record", granted: permissions.screenRecording) {
                    permissions.requestScreenRecording()
                }
            } footer: {
                if !permissions.screenRecording {
                    Text("目前以無縮圖模式運作：預覽顯示 App 圖示和視窗標題，切換、關閉、縮小照常可用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }
}

/// 權限狀態列：左側功能圖示＋名稱，右側已授權顯示綠勾、未授權顯示前往按鈕。
private struct PermissionRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingsIconTile(symbol: symbol, tint: granted ? .green : .orange, size: 22)
            Text(title)
            Spacer()
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

// MARK: - 共用

/// 滑桿＋右側數值。數值欄用最小寬度＋不換行而非固定寬度：單位長度因語言而異（ms／毫秒／миллисекунд）。
private struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// 數值文字；呼叫端用 `Text("\(…) pt")` 以沿用字串目錄裡各語言的單位翻譯
    let format: (Double) -> Text

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: step)
            format(value)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}
