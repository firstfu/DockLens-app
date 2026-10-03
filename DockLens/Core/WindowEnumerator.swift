//
//  WindowEnumerator.swift
//  DockLens
//
//  列舉某個 App 目前有哪些「使用者看得到的視窗」。
//  資料來源合併兩者：
//  - Accessibility（AX）：權威清單，能分辨標準視窗/對話框、知道是否最小化、並提供關閉/縮小等操作入口；
//    但只回傳「目前桌面（Space）」上的視窗。
//  - CGWindowList：涵蓋所有 Space，也提供前後層次（z-order）；但混有大量隱藏的輔助視窗（例如自動填寫面板）。
//  以 AX 為主、CG 補上其他 Space 的具名視窗，兼顧正確性與完整性。
//  沒有螢幕錄製權限時 CG 不給其他 App 的視窗標題，其他 Space／已關閉的視窗改以 AX 遠端元素讀標題。
//

import AppKit

/// 單一視窗的快照資訊。
nonisolated struct WindowInfo: Identifiable, Sendable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    var title: String
    /// 視窗外框（points、CG 全域座標）
    var frame: CGRect
    var isMinimized: Bool
    /// 視窗是否位於其他桌面（Space）；此類視窗沒有 AX 元素，無法關閉/縮小，只能切換過去
    var isOnOtherSpace: Bool
    /// AX 元素，供關閉/縮小/前置等操作；其他 Space 的視窗為 nil
    let ax: AXRef?
    /// 按 X 關掉、但 App 仍保留著的視窗（Notion、Slack 等按 X 只是把主視窗藏起來）。
    /// 沒辦法直接叫出別的 App 的隱藏視窗，點擊時改為「重新打開 App」（等同點 Dock 圖示），由 App 自己把視窗叫回來。
    var isClosed = false
    /// 視窗所開啟的文件位置（AXDocument）；沒有文件的視窗為 nil。用來判斷「最近關閉」的檔案現在是否又開著
    var documentURL: URL?

    /// 視窗寬高比，用來決定縮圖卡片大小（在影像還沒拍到前就能先排版，避免面板跳動）
    var aspectRatio: CGFloat {
        guard frame.height > 1 else { return 16.0 / 10.0 }
        return frame.width / frame.height
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.frame == rhs.frame
            && lhs.isMinimized == rhs.isMinimized && lhs.isOnOtherSpace == rhs.isOnOtherSpace
            && lhs.isClosed == rhs.isClosed
    }
}

nonisolated enum WindowEnumerator {
    /// 小於此尺寸的視窗視為工具面板/雜訊，不列入預覽
    private static let minimumSide: CGFloat = 60
    /// AX 呼叫逾時：遇到卡死的 App 時避免拖住整個預覽（系統預設高達 6 秒）。
    /// 不能設太短：系統忙碌時正常 App 也可能要數百毫秒才回應（實測負載 9 時超過 0.25 秒），太短會誤判成沒有視窗。
    private static let axTimeout: Float = 1.0

    /// 列舉指定 App 的可預覽視窗，依「最近使用」排序（最前面的視窗在前、最小化視窗在後）。
    ///
    /// 成本：CGWindowList ~2–3ms + 每個視窗數個 AX IPC，通常 < 10ms；請在背景執行緒呼叫。
    /// - Parameters:
    ///   - pid: 目標 App 的 pid
    ///   - includeOtherSpaces: 是否納入其他桌面上的視窗
    ///   - includeClosed: App 沒有任何開著的視窗時，是否納入「按 X 關掉但仍保留」的視窗（供點擊重新打開）
    ///   - windowServerTitles: CGWindowList 是否給得出標題（= 有螢幕錄製權限）；false 時忽略 CG 標題、改讀 AX
    /// - Returns: 視窗清單（可能為空）
    static func windows(
        for pid: pid_t, includeOtherSpaces: Bool, includeClosed: Bool = false,
        windowServerTitles: Bool = ScreenRecordingAccess.isGranted
    ) -> [WindowInfo] {
        var cgWindows = cgWindowList(for: pid, includesTitles: windowServerTitles)
        // CGWindowList 由前到後排列，索引即 z-order
        var zOrder: [CGWindowID: Int] = [:]
        for (index, entry) in cgWindows.enumerated() { zOrder[entry.id] = index }
        let cgByID = Dictionary(cgWindows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var rawWindows: CFTypeRef?
        let axStatus = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        let axWindows = (rawWindows as? [AXUIElement]) ?? []

        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        // ⌘H 隱藏的 App 其視窗在 CG 也是不在畫面上，不能因此當成幽靈視窗
        let appIsHidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
        let attributes = [
            kAXRoleAttribute as String, kAXSubroleAttribute as String, kAXMinimizedAttribute as String,
            kAXTitleAttribute as String, kAXPositionAttribute as String, kAXSizeAttribute as String,
            "AXDocument",
        ]
        for window in axWindows {
            // 每個視窗只做一次批次 IPC，而非 6 次個別呼叫
            let values = window.values(attributes)
            guard values[kAXRoleAttribute as String] as? String == kAXWindowRole as String,
                  let subrole = values[kAXSubroleAttribute as String] as? String,
                  subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String,
                  let id = window.windowID, !seen.contains(id) else { continue }
            let cg = cgByID[id]
            let minimized = values[kAXMinimizedAttribute as String] as? Bool ?? false
            // 非最小化卻不存在於 CG 清單的，多半是已關閉但 AX 尚未更新的殭屍元素
            guard cg != nil || minimized else { continue }
            let axFrame: CGRect? = {
                guard let origin = AXUIElement.point(values[kAXPositionAttribute as String]),
                      let size = AXUIElement.size(values[kAXSizeAttribute as String]) else { return nil }
                return CGRect(origin: origin, size: size)
            }()
            let frame = cg?.frame ?? axFrame ?? .zero
            guard frame.width >= minimumSide, frame.height >= minimumSide else { continue }

            let axTitle = values[kAXTitleAttribute as String] as? String ?? ""
            let title = axTitle.isEmpty ? (cg?.title ?? "") : axTitle
            // 無標題的視窗多半是 App 自己的輔助視窗（cmux、Electron 的浮動面板／離屏 Dialog），
            // 使用者看不到也拍不出縮圖，卡片只會顯示「未命名視窗」的空白。
            // 無標題的 Dialog 一律略過；無標題的標準視窗只在「畫面上或最小化或 App 被隱藏」時保留。
            if title.isEmpty {
                if subrole == kAXDialogSubrole as String { continue }
                if !minimized, cg?.isOnScreen != true, !appIsHidden { continue }
            }
            seen.insert(id)
            result.append(WindowInfo(
                id: id, pid: pid,
                title: title,
                frame: frame,
                isMinimized: minimized,
                isOnOtherSpace: false,
                ax: AXRef(element: window),
                documentURL: ClosedWindowPolicy.documentURL(from: values["AXDocument"])
            ))
        }

        // AX 查詢失敗（App 忙碌逾時、不支援輔助使用）時，改以 CG 清單中「畫面上、具標題」的視窗補上，
        // 至少能預覽與切換（沒有 AX 元素就無法關閉/縮小）
        if axStatus != .success && axStatus != .noValue {
            for cg in cgWindows where !seen.contains(cg.id) && cg.isOnScreen && !cg.title.isEmpty
                && cg.frame.width >= minimumSide && cg.frame.height >= minimumSide {
                seen.insert(cg.id)
                result.append(WindowInfo(
                    id: cg.id, pid: pid, title: cg.title, frame: cg.frame,
                    isMinimized: false, isOnOtherSpace: false, ax: nil
                ))
            }
        }

        // 不在畫面上、AX 也看不到的一般視窗，依 WindowServer 狀態分三類：
        // - 不屬於任何 Space：被收起的隱藏輔助視窗（例如 Electron 的 500×500 隱藏視窗）→ 略過
        // - 仍「排在」某個 Space 上（ordered in）：在其他桌面 → 可切換過去
        // - 屬於某個 Space 但「沒排上」（ordered out）：按 X 關掉但 App 還保留（實測 Notion 即是）→ 可重新打開
        // 私有 API 不可用時退回「具標題」的保守條件，一律視為其他桌面。
        var closedCandidates: [CGEntry] = []
        // App 沒回應（AX 逾時）時不補標題：掃描要對它做上千次 AX 呼叫，每次都可能等到逾時
        let axResponded = axStatus == .success || axStatus == .noValue
        if !windowServerTitles && axResponded && (includeOtherSpaces || includeClosed) {
            cgWindows = fillingTitles(cgWindows, pid: pid, excluding: seen)
        }
        if includeOtherSpaces || includeClosed {
            for cg in cgWindows where !seen.contains(cg.id) && isOffscreenCandidate(cg) {
                let spaces = SkyLight.spaces(for: cg.id)
                if let spaces, spaces.isEmpty { continue }
                if spaces == nil && cg.title.isEmpty { continue }
                if SkyLight.isOrderedIn(cg.id) == false {
                    if !cg.title.isEmpty { closedCandidates.append(cg) }
                    continue
                }
                guard includeOtherSpaces else { continue }
                seen.insert(cg.id)
                result.append(WindowInfo(
                    id: cg.id, pid: pid, title: cg.title, frame: cg.frame,
                    isMinimized: false, isOnOtherSpace: true, ax: nil
                ))
            }
        }
        // 只有在 App 完全沒有開著（含縮小、其他桌面）的視窗時才列出，且只列最大的一個（通常就是主視窗）：
        // App 有其他視窗時，藏起來的多半是設定面板之類的輔助視窗，列出來只是雜訊。
        if includeClosed, result.isEmpty,
           let main = closedCandidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            result.append(WindowInfo(
                id: main.id, pid: pid, title: main.title, frame: main.frame,
                isMinimized: false, isOnOtherSpace: false, ax: nil, isClosed: true
            ))
        }

        result.sort { lhs, rhs in
            if lhs.isMinimized != rhs.isMinimized { return !lhs.isMinimized }
            return (zOrder[lhs.id] ?? .max) < (zOrder[rhs.id] ?? .max)
        }
        return result
    }

    /// 不在畫面上、夠大到可能是真實視窗的 CG 項目（其他桌面或已關閉的候選）。
    private static func isOffscreenCandidate(_ cg: CGEntry) -> Bool {
        !cg.isOnScreen && cg.frame.width >= 200 && cg.frame.height >= 150
    }

    /// 沒有螢幕錄製權限時，替「不在畫面上、屬於某個桌面、沒有標題」的候選視窗從 AX 補上標題。
    /// 先用 Space 過濾掉被收起的輔助視窗（例如 Electron 的隱藏視窗），沒有候選就不掃描，省下約 20ms。
    /// 私有 API 不可用時原樣回傳：這些視窗沒有標題，之後的規則會把它們略過（少列，但不會列錯）。
    private static func fillingTitles(_ entries: [CGEntry], pid: pid_t, excluding seen: Set<CGWindowID>) -> [CGEntry] {
        let missing = Set(entries.lazy.filter { cg in
            !seen.contains(cg.id) && cg.title.isEmpty && isOffscreenCandidate(cg)
                && SkyLight.spaces(for: cg.id)?.isEmpty != true
        }.map(\.id))
        guard !missing.isEmpty else { return entries }
        let titles = AXRemote.titles(pid: pid, windowIDs: missing)
        guard !titles.isEmpty else { return entries }
        return entries.map { cg in
            titles[cg.id].map { CGEntry(id: cg.id, title: $0, frame: cg.frame, isOnScreen: cg.isOnScreen) } ?? cg
        }
    }

    // MARK: - CGWindowList

    private struct CGEntry {
        let id: CGWindowID
        let title: String
        let frame: CGRect
        let isOnScreen: Bool
    }

    /// 取得指定 pid 的一般層級（layer 0）、非全透明視窗。
    /// - Parameter includesTitles: false 時一律不取標題（模擬沒有螢幕錄製權限時的系統行為，讓自我測試與實際一致）
    private static func cgWindowList(for pid: pid_t, includesTitles: Bool) -> [CGEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var entries: [CGEntry] = []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            entries.append(CGEntry(
                id: id,
                title: includesTitles ? info[kCGWindowName as String] as? String ?? "" : "",
                frame: bounds,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
            ))
        }
        return entries
    }
}
