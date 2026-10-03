//
//  Permissions.swift
//  DockLens
//
//  兩項權限的狀態追蹤與請求：
//  - 輔助使用（Accessibility）：**必要**。讀取 Dock 游標位置、列舉/操作其他 App 的視窗、讀視窗標題
//  - 螢幕錄製（Screen Recording）：**選用**。擷取視窗縮圖；WindowServer 也只在有此權限時才給其他 App 的視窗標題。
//    沒有時以「無縮圖模式」運作（卡片只顯示 App 圖示與標題），切換、關閉、縮小照常可用。
//  系統不會通知權限變更，因此在引導期間每秒輪詢一次；全部授權或使用者關掉引導後停止輪詢。
//

import AppKit
import ApplicationServices
import Observation

/// 螢幕錄製權限的唯一判斷入口（任何執行緒可呼叫）。
/// 擷取前一律先問這裡：沒有權限時呼叫 ScreenCaptureKit 會再次跳出系統的授權詢問。
nonisolated enum ScreenRecordingAccess {
    /// 自我測試用：模擬沒有螢幕錄製權限，不必真的撤銷系統授權（撤銷後要使用者手動再開）
    static let isSimulatedOff = ProcessInfo.processInfo.arguments.contains("--simulate-no-screen-recording")

    /// 目前是否可擷取視窗畫面、讀到 WindowServer 的視窗標題。
    static var isGranted: Bool { !isSimulatedOff && CGPreflightScreenCaptureAccess() }
}

@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = ScreenRecordingAccess.isGranted

    var allGranted: Bool { accessibility && screenRecording }

    /// 輔助使用由未授權變為已授權時呼叫一次（此時即可開始運作）
    @ObservationIgnored var onAccessibilityGranted: (() -> Void)?
    /// 全部授權完成時呼叫一次
    @ObservationIgnored var onAllGranted: (() -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// 重新讀取權限狀態，並觸發對應的回呼。
    /// 值沒變就不寫回：@Observable 每次賦值都會通知，沒必要讓設定頁、選單跟著重繪。
    func refresh() {
        let wasRunnable = accessibility
        let wasGranted = allGranted
        let ax = AXIsProcessTrusted()
        let screen = ScreenRecordingAccess.isGranted
        if ax != accessibility { accessibility = ax }
        if screen != screenRecording { screenRecording = screen }
        if !wasRunnable && accessibility { onAccessibilityGranted?() }
        if !wasGranted && allGranted { onAllGranted?() }
    }

    /// 每秒輪詢，直到全部授權或呼叫 `stopPolling()`。
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if self.allGranted { self.pollTask = nil; return }
            }
        }
    }

    /// 停止輪詢（使用者選擇不給螢幕錄製時，閒置不該每秒喚醒）。
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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
