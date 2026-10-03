//
//  ClosedWindowStore.swift
//  DockLens
//
//  「最近關閉」清單：記下使用者剛關掉的文件視窗（App ＋ 檔案路徑），之後能在 Dock 圖示的預覽面板上一鍵重開。
//  只存在記憶體裡：結束 DockLens 就清空，不寫入磁碟、不連網，與「資料不離開這台 Mac」的承諾一致。
//  只收「檔案」視窗（AXDocument 為 file URL）：瀏覽器的網址可能來自隱私視窗、也已有自己的「重新開啟已關閉的視窗」，
//  Terminal、Slack 這類沒有檔案的視窗根本無從還原，兩者一律不記。
//

import Foundation

/// 一筆被關掉的視窗。
nonisolated struct ClosedWindowEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    /// 所屬 App 的 bundle id；預覽面板用它找出「這個 App 的紀錄」
    let bundleID: String
    /// 視窗標題（App 可能附上「已編輯」之類的狀態文字，只供參考）
    let title: String
    /// 重開時交給 App 開啟的檔案或資料夾
    let url: URL
    let closedAt: Date

    init(id: UUID = UUID(), bundleID: String, title: String, url: URL, closedAt: Date = Date()) {
        self.id = id
        self.bundleID = bundleID
        self.title = title
        self.url = url
        self.closedAt = closedAt
    }

    /// 清單上顯示的名稱：檔案或資料夾名稱（比視窗標題穩定，不含「— 已編輯」之類的後綴）。
    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? title : name
    }

    /// 檔案所在資料夾的名稱，同名檔案靠它分辨；根目錄沒有上層時為空字串。
    var parentName: String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent == "/" ? "" : parent
    }
}

nonisolated enum ClosedWindowPolicy {
    /// 這個 AXDocument 值能不能拿來「重開」：只收仍存在於本機的 file URL。
    /// - Parameter url: 視窗回報的文件位置
    static func isRestorable(_ url: URL?) -> Bool {
        guard let url, url.isFileURL, !url.path.isEmpty else { return false }
        // 檔案被丟進垃圾桶之後才關視窗：重開只會打開垃圾桶裡的檔案，不是使用者想要的
        return !url.pathComponents.contains(".Trash")
    }

    /// 把 AX 屬性值（字串或 URL）轉成 URL；不是 URL 的值（例如空字串）回傳 nil。
    static func documentURL(from value: CFTypeRef?) -> URL? {
        if let url = value as? URL { return url }
        guard let string = value as? String, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    /// 比對用的檔案識別：展開符號連結（`/tmp` 與 `/private/tmp` 要視為同一個）。
    /// 視窗列舉與紀錄各自拿到的路徑寫法可能不同，直接比字串會漏掉「已經重新打開」的判斷。
    static func key(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        // 系統只在檔案「存在」時才會把 /private/tmp 化簡成 /tmp；檔案已被刪掉時兩種寫法並存，這裡補上同樣的化簡
        for prefix in ["/private/tmp", "/private/var", "/private/etc"] where path == prefix || path.hasPrefix(prefix + "/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}

/// 最近關閉清單（最新在前）。僅供主執行緒使用。
final class ClosedWindowStore {
    /// 清單最多保留幾筆（所有 App 合計）；舊的自動擠掉
    static let capacity = 40
    /// 面板上每個 App 最多列幾筆：太多會把面板撐得很高，也不是「剛關掉」的情境
    static let panelLimit = 4

    private(set) var entries: [ClosedWindowEntry] = []
    /// 新增一筆後呼叫（預覽面板開著時用它即時補上剛關掉的項目）
    var onAdd: ((ClosedWindowEntry) -> Void)?

    /// 同一個檔案在這段時間內重複進來，視為同一次關閉（見 `add`）
    static let duplicateWindow: TimeInterval = 3

    /// 新增一筆；同一個 App 同一個檔案只留最新的一筆（反覆開關同一份文件不會把清單塞滿）。
    /// 從面板按 X 關閉時會先記一筆（面板立刻要顯示），幾百毫秒後偵測機制又報同一次關閉：
    /// 3 秒內的重複不再新增一筆（清單內容不變），只通知一次讓面板重新判斷。
    /// - Parameter notify: 是否呼叫 `onAdd`；呼叫端自己會更新畫面時傳 false
    func add(_ entry: ClosedWindowEntry, notify: Bool = true) {
        let key = ClosedWindowPolicy.key(entry.url)
        if let existing = entries.first(where: { $0.bundleID == entry.bundleID && ClosedWindowPolicy.key($0.url) == key }),
           abs(entry.closedAt.timeIntervalSince(existing.closedAt)) < Self.duplicateWindow {
            // 內容不變，但仍通知：面板上按 X 時那一筆在面板更新當下可能被「視窗還沒消失」濾掉，
            // 偵測機制稍後的這次回報是讓面板重新判斷的機會
            if notify { onAdd?(existing) }
            return
        }
        entries.removeAll { $0.bundleID == entry.bundleID && ClosedWindowPolicy.key($0.url) == key }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        if notify { onAdd?(entry) }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func removeAll() {
        entries.removeAll()
    }

    /// 移除某個 App 最近這段時間內新增的紀錄。
    /// App 結束得慢（要存檔、跳詢問）時，視窗會一個個被銷毀，晚於偵測的確認時間才真的結束，
    /// 這些文件會被當成「剛關掉」記下來——App 結束後把這段時間內的紀錄清掉。
    /// - Parameters:
    ///   - bundleID: 結束的 App
    ///   - interval: 往回多少秒內新增的算數
    ///   - now: 現在時間（測試用注入）
    func removeRecent(bundleID: String, within interval: TimeInterval, now: Date = Date()) {
        entries.removeAll { $0.bundleID == bundleID && now.timeIntervalSince($0.closedAt) < interval }
    }

    /// 某個 App 該顯示的紀錄：略過「現在已經開著」的文件與已不存在的檔案。
    /// - Parameters:
    ///   - bundleID: 目標 App
    ///   - openKeys: 目前開著的文件（`ClosedWindowPolicy.key`）；使用者已用別的方式重開就不必再列
    ///   - limit: 最多幾筆
    ///   - exists: 檔案是否仍存在（測試用注入）
    func entries(
        for bundleID: String, excludingOpen openKeys: Set<String> = [], limit: Int = ClosedWindowStore.panelLimit,
        exists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [ClosedWindowEntry] {
        Self.visible(entries.filter { $0.bundleID == bundleID }, excludingOpen: openKeys, limit: limit, exists: exists)
    }

    /// 從候選中挑出面板該顯示的（新的在前）：略過已經開著的與已不存在的。
    /// 做成純函式放在主執行緒之外執行：檔案存在檢查與路徑解析要碰檔案系統，
    /// 紀錄指向斷線的網路磁碟時可能阻塞數秒，不能卡住面板。
    nonisolated static func visible(
        _ candidates: [ClosedWindowEntry], excludingOpen openKeys: Set<String>, limit: Int,
        exists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [ClosedWindowEntry] {
        var result: [ClosedWindowEntry] = []
        for entry in candidates {
            guard !openKeys.contains(ClosedWindowPolicy.key(entry.url)), exists(entry.url) else { continue }
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }
}
