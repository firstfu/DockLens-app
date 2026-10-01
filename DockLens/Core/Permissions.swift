//
//  Permissions.swift
//  DockLens
//
//  兩項必要權限的狀態追蹤與請求：
//  - 輔助使用（Accessibility）：讀取 Dock 游標位置、列舉/操作其他 App 的視窗
//  - 螢幕錄製（Screen Recording）：擷取視窗縮圖、讀取視窗標題
//  系統不會通知權限變更，因此在尚未全部授權時每秒輪詢一次；全部授權後停止輪詢。
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    var allGranted: Bool { accessibility && screenRecording }

    /// 全部授權完成時呼叫一次
    @ObservationIgnored var onAllGranted: (() -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// 重新讀取權限狀態；若由未授權變為全部授權則觸發 `onAllGranted`。
    func refresh() {
        let wasGranted = allGranted
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        if !wasGranted && allGranted { onAllGranted?() }
    }

    /// 在尚未全部授權期間每秒輪詢。
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refresh()
                if self.allGranted { self.pollTask = nil; return }
            }
        }
    }

    /// 跳出系統的輔助使用授權提示，並打開對應的系統設定頁。
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// 請求螢幕錄製權限；系統通常只在第一次顯示提示，之後需到系統設定手動開啟。
    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
