//
//  MediaController.swift
//  DockLens
//
//  音樂 App（Spotify、音樂）的播放控制：以 AppleScript 控制「游標所在的那個 App」並讀取目前歌曲。
//  為什麼用 AppleScript 而不是媒體鍵：媒體鍵只會送給系統的「正在播放」App，不一定是游標下的那個，
//  也讀不到歌名與播放狀態。代價是需要「自動化」權限（每個目標 App 各授權一次）。
//  為了不在游標停上圖示時就跳出授權詢問，顯示前先以 `AEDeterminePermissionToAutomateTarget`
//  「不詢問」地檢查；使用者第一次按播放鈕時才讓系統詢問。
//

import AppKit
import CoreServices
import os

/// 支援播放控制的 App。
nonisolated enum MediaPlayer: Sendable, Equatable {
    case spotify, music

    /// 依 bundle id 判斷；不支援的 App 回傳 nil。
    init?(bundleID: String?) {
        switch bundleID {
        case "com.spotify.client": self = .spotify
        case "com.apple.Music": self = .music
        default: return nil
        }
    }

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    /// 介面上顯示的名稱
    var displayName: String { self == .spotify ? "Spotify" : String(localized: "音樂", comment: "Apple 的「音樂」App，請用該語言 macOS 上的 App 名稱") }
}

/// 播放指令；rawValue 為 Spotify 與音樂共用的 AppleScript 指令。
nonisolated enum MediaCommand: String, Sendable {
    case playPause = "playpause"
    case next = "next track"
    case previous = "previous track"
}

/// 目前播放的歌曲。
nonisolated struct NowPlaying: Sendable, Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
}

/// 播放列要呈現的狀態。
nonisolated enum MediaStatus: Sendable, Equatable {
    /// 尚未查詢
    case loading
    /// 尚未授權「自動化」；按下播放鈕時才詢問使用者
    case needsPermission
    /// 使用者拒絕授權
    case denied
    /// 沒有歌曲（停止）
    case stopped
    case track(NowPlaying)
    /// 其他錯誤（App 沒回應等）
    case unavailable
}

nonisolated enum MediaController {
    /// AppleScript 一律在這條序列佇列執行：會等目標 App 回覆，第一次還會等使用者回應授權詢問，不能卡住主執行緒。
    private static let queue = DispatchQueue(label: "com.firstfu.DockLens.media", qos: .userInitiated)
    private static let log = Logger(subsystem: "com.firstfu.DockLens", category: "media")

    /// 「自動化」權限被拒（errAEEventNotPermitted）
    private static let notPermitted: OSStatus = -1743
    /// 尚未決定、需要詢問使用者（errAEEventWouldRequireUserConsent）
    private static let wouldRequireConsent: OSStatus = -1744

    /// 讀取目前播放狀態；尚未授權時不會跳出詢問。
    /// - Parameter player: 目標 App（必須正在執行，否則 AppleScript 會把它啟動）
    /// - Returns: 播放列狀態
    static func status(of player: MediaPlayer) async -> MediaStatus {
        await run {
            let permitted = permission(for: player, askUserIfNeeded: false)
            log.notice("自動化權限檢查 \(player.displayName, privacy: .public)：\(permitted)")
            switch permitted {
            case noErr: return queryStatus(of: player)
            case wouldRequireConsent: return .needsPermission
            case notPermitted: return .denied
            default: return .unavailable
            }
        }
    }

    /// 送出播放指令（未授權時由系統詢問使用者），再回傳最新狀態。
    /// - Parameters:
    ///   - command: 播放指令
    ///   - player: 目標 App
    /// - Returns: 指令執行後的狀態
    static func send(_ command: MediaCommand, to player: MediaPlayer) async -> MediaStatus {
        log.notice("送出指令 \(command.rawValue, privacy: .public) → \(player.displayName, privacy: .public)")
        return await run {
            let result = execute("tell application id \"\(player.bundleID)\" to \(command.rawValue)")
            log.notice("指令結果：\(String(describing: result), privacy: .public)")
            switch result {
            case .success: return queryStatus(of: player)
            case .failure(let code) where code == Int(notPermitted): return .denied
            case .failure: return .unavailable
            }
        }
    }

    // MARK: - 內部

    private static func run(_ work: @escaping @Sendable () -> MediaStatus) async -> MediaStatus {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// 檢查（必要時詢問）對目標 App 的「自動化」權限。目標 App 未執行時回傳 procNotFound（-600）。
    private static func permission(for player: MediaPlayer, askUserIfNeeded: Bool) -> OSStatus {
        var address = AEAddressDesc()
        let bundleID = Data(player.bundleID.utf8)
        let created = bundleID.withUnsafeBytes { AECreateDesc(typeApplicationBundleID, $0.baseAddress, bundleID.count, &address) }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&address) }
        return AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, askUserIfNeeded)
    }

    /// 讀取播放狀態與歌曲（需已授權）。
    private static func queryStatus(of player: MediaPlayer) -> MediaStatus {
        let script = """
        tell application id "\(player.bundleID)"
            set s to player state as string
            if s is "stopped" then return "stopped"
            return s & linefeed & (name of current track) & linefeed & (artist of current track)
        end tell
        """
        guard case .success(let output) = execute(script) else { return .unavailable }
        let lines = output.components(separatedBy: "\n")
        guard lines.first != "stopped", lines.count >= 3 else { return .stopped }
        return .track(NowPlaying(title: lines[1], artist: lines[2], isPlaying: lines[0] == "playing"))
    }

    private enum ScriptResult { case success(String), failure(Int) }

    /// 編譯並執行 AppleScript。
    /// - Returns: 成功時為字串結果；失敗時為 AppleScript 錯誤碼（-1743 為未授權）
    private static func execute(_ source: String) -> ScriptResult {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            return .failure(error?[NSAppleScript.errorNumber] as? Int ?? 0)
        }
        return .success(result.stringValue ?? "")
    }
}
