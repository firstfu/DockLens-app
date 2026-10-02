//
//  DockLensApp.swift
//  DockLens
//
//  App 進入點。DockLens 是常駐選單列的 agent App（LSUIElement，無 Dock 圖示），
//  提供 MenuBarExtra 選單與 Settings 設定視窗；實際工作由 AppCoordinator 統籌。
//

import SwiftUI

@main
struct DockLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(coordinator: coordinator)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings {
            SettingsView(coordinator: coordinator)
        }
    }

    /// 有新版本時改顯示下載箭頭，讓沒打開選單的人也看得到
    private var menuBarSymbol: String {
        if coordinator.updates.availableUpdate != nil { return "arrow.down.circle" }
        return coordinator.settings.isEnabled ? "rectangle.on.rectangle" : "rectangle.on.rectangle.slash"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared.launch()
        // 安裝腳本用：`open DockLens.app --args --register-login-item` 直接註冊登入項目
        if CommandLine.arguments.contains("--register-login-item") {
            AppSettings.shared.launchAtLogin = true
        }
        if CommandLine.arguments.contains("--probe-label") {
            Task { await SelfTest.probeLabel(coordinator: AppCoordinator.shared) }
        } else if SelfTest.isRequested {
            Task { await SelfTest.run(coordinator: AppCoordinator.shared) }
        }
    }
}

/// 選單列下拉選單。
private struct MenuContent: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var settings = coordinator.settings
        if let update = coordinator.updates.availableUpdate {
            Button("下載新版本 \(update.version)…") { coordinator.updates.openDownloadPage() }
            Divider()
        }
        Toggle("啟用視窗預覽", isOn: $settings.isEnabled)
            .keyboardShortcut("e")
        if !coordinator.permissions.allGranted {
            Button("授予權限…") { coordinator.showOnboarding() }
        }
        Divider()
        Button("設定…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("檢查更新…") {
            Task {
                await coordinator.updates.check()
                // 從選單手動檢查時要有回應：有新版直接開下載頁，否則打開設定看結果
                if coordinator.updates.availableUpdate != nil {
                    coordinator.updates.openDownloadPage()
                } else {
                    NSApp.activate()
                    openSettings()
                }
            }
        }
        Divider()
        Button("結束 DockLens") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
