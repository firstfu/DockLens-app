//
//  ClosedWindowWatcher.swift
//  DockLens
//
//  偵測「某個 App 的文件視窗被關掉了」，並交出當時的檔案路徑，供「最近關閉」清單使用。
//  做法：對使用者用過的 App 掛 AXObserver，每個視窗註冊 `AXUIElementDestroyed`。
//  視窗銷毀後再讀它的屬性只會得到錯誤（實測 TextEdit：-25202），所以標題與 AXDocument 必須「在視窗還活著時」預先記下，
//  並隨 `AXTitleChanged`（存檔、另存新檔、換文件都會改標題）更新。
//  完全事件驅動、沒有輪詢，閒置時不佔 CPU。
//
//  為什麼只在 App「被切到前景」時才掛：對每個 App 都掛，等於一啟動就逐一向所有 App 做 AX 查詢，
//  Chromium／Electron 類 App 偵測到輔助使用的用戶端後會改走較耗資源的路徑。使用者沒碰過的 App 不可能被他關視窗。
//  為什麼用專屬執行緒：AXObserverAddNotification 與屬性讀取都是對目標 App 的同步 IPC，遇到沒回應的 App 最多等逾時，
//  不能放在主執行緒卡住畫面。
//

import AppKit
import ApplicationServices
import os

nonisolated final class ClosedWindowWatcher: @unchecked Sendable {
    /// 一個被關掉的視窗。
    struct Closed: Sendable {
        let pid: pid_t
        let bundleID: String
        let title: String
        let url: URL
        let closedAt: Date
    }

    /// 視窗銷毀後等多久才回報：App 結束時會一口氣銷毀所有視窗，這不是「使用者關掉視窗」，
    /// 要等一下確認 App 還活著才算。
    private static let confirmDelay: Double = 0.6
    /// 對目標 App 的 AX 呼叫逾時（秒）。與 `WindowEnumerator` 同值，理由見 window-enumeration.md。
    private static let axTimeout: Float = 1.0

    private let log = Logger(subsystem: "com.firstfu.DockLens", category: "closed-windows")

    private struct Record {
        let pid: pid_t
        var title: String
        var url: URL?
    }

    /// 回報在主佇列上呼叫
    private let onClosed: @Sendable (Closed) -> Void
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    /// `stop()` 之後 run loop 不再執行排進去的工作；擋住新的呼叫，免得有人等一個永遠不會跑的 block
    private let stateLock = NSLock()
    private var isStopped = false

    // 以下狀態只在 watcher 執行緒存取，不加鎖
    private var observers: [pid_t: AXObserver] = [:]
    private var bundleIDs: [pid_t: String] = [:]
    private var records: [AXUIElement: Record] = [:]

    /// 啟動專屬執行緒。
    /// - Parameter onClosed: 偵測到視窗被關掉時在主佇列呼叫
    init(onClosed: @escaping @Sendable (Closed) -> Void) {
        self.onClosed = onClosed
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            // 沒有任何 source 時 run loop 會立刻返回；放一個永遠不會觸發的 port 讓它留著等 observer 加進來
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.firstfu.DockLens.closed-window-watcher"
        thread.qualityOfService = .utility
        thread.start()
        ready.wait()
    }

    /// 開始（或重新整理）監看某個 App 的視窗。已在監看時只重讀既有視窗的標題與文件位置，並補掛新視窗。
    func attach(pid: pid_t, bundleID: String) {
        perform { $0.attachNow(pid: pid, bundleID: bundleID, attempt: 0) }
    }

    /// 停止監看並丟掉該 App 的紀錄（App 結束時呼叫）。
    func detach(pid: pid_t) {
        perform { $0.detachNow(pid: pid) }
    }

    /// 停止監看並結束專屬執行緒（關閉設定時）。呼叫後這個實例不能再用。
    func stop() {
        perform { watcher in
            for pid in Array(watcher.observers.keys) { watcher.detachNow(pid: pid) }
            watcher.stateLock.withLock { watcher.isStopped = true }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// 目前掛著幾個 App、記著幾個視窗（自我測試與除錯用；同步等待 watcher 執行緒）。
    /// - Parameter pid: 只算這個 App 的視窗；nil 為全部（包含使用者平常在用的 App，數字會隨他的操作變動）
    func statistics(pid: pid_t? = nil) -> (apps: Int, windows: Int) {
        // 結果在 watcher 執行緒寫入、之後由 semaphore 保證呼叫端才讀，用盒子跨過 Sendable 檢查
        final class Box: @unchecked Sendable { var apps = 0, windows = 0 }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        perform { watcher in
            box.apps = watcher.observers.count
            box.windows = pid.map { pid in watcher.records.values.filter { $0.pid == pid }.count } ?? watcher.records.count
            done.signal()
        }
        // 逾時保險：watcher 已停止（或卡住）時不要永遠等下去
        guard done.wait(timeout: .now() + 2) == .success else { return (0, 0) }
        return (box.apps, box.windows)
    }

    /// 每筆紀錄的摘要（標題、檔名、以及現在讀它的角色屬性得到的結果代碼）；自我測試失敗時用來看殘留的是什麼。
    func recordSummaries(pid: pid_t? = nil) -> [String] {
        final class Box: @unchecked Sendable { var lines: [String] = [] }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        perform { watcher in
            box.lines = watcher.records.filter { pid == nil || $0.value.pid == pid }.map { window, record in
                var raw: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &raw)
                return "\(record.title)｜\(record.url?.lastPathComponent ?? "-")｜讀取結果 \(status.rawValue)"
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + 2) == .success else { return [] }
        return box.lines
    }

    private func perform(_ block: @escaping @Sendable (ClosedWindowWatcher) -> Void) {
        guard let runLoop, !stateLock.withLock({ isStopped }) else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { block(self) }
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - 掛載（watcher 執行緒）

    private func attachNow(pid: pid_t, bundleID: String, attempt: Int) {
        if let observer = observers[pid] {
            refresh(pid: pid, observer: observer)
            return
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // App 還沒準備好（剛啟動）或不支援輔助使用時會失敗：不記，等下一次切到前景再試
        let status = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        guard status == .success, let runLoop else {
            // 剛啟動的 App 還沒開始處理輔助使用請求（-25204 cannotComplete）：App 一被切到前景就來掛，常常太早。
            // 隔半秒再試，最多約 4 秒；之後仍可由下一次切到前景或預覽面板顯示時重新嘗試。
            log.notice("掛上 pid \(pid) 失敗：\(status.rawValue)（第 \(attempt + 1) 次）")
            if attempt < 8, NSRunningApplication(processIdentifier: pid)?.isTerminated == false {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [self] in
                    perform { $0.attachNow(pid: pid, bundleID: bundleID, attempt: attempt + 1) }
                }
            }
            return
        }
        // 文件是視窗建立「之後」才設上去的 App，AXDocument 在建立當下還是空的，也沒有專屬的通知；
        // 視窗拿到焦點／成為主視窗時重讀一次，補上這段空窗
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        bundleIDs[pid] = bundleID
        refresh(pid: pid, observer: observer)
    }

    private func detachNow(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid), let runLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        bundleIDs[pid] = nil
        records = records.filter { $0.value.pid != pid }
    }

    /// 讀出 App 目前所有視窗：新的補掛通知、舊的更新標題與文件位置。
    private func refresh(pid: pid_t, observer: AXObserver) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axTimeout)
        guard let windows: [AXUIElement] = app.value(kAXWindowsAttribute) else { return }
        for window in windows { watch(window, pid: pid, observer: observer) }
        pruneInvalidRecords(pid: pid, alive: Set(windows))
    }

    /// 丟掉「視窗其實已經不存在」的紀錄。
    /// 為什麼會有：視窗剛被關掉時，App 回報的視窗清單偶爾還帶著它（實測反覆開關 150 次會殘留 1～3 筆），
    /// 若剛好在「銷毀通知已經送出」之後才為它註冊，就永遠等不到通知，紀錄會一直留著。
    /// 不在清單內、又讀不到屬性（invalidUIElement）才算失效；在其他桌面的視窗不在清單內，但讀得到，會保留。
    private func pruneInvalidRecords(pid: pid_t, alive: Set<AXUIElement>) {
        for (window, record) in records where record.pid == pid && !alive.contains(window) {
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &raw) == .invalidUIElement {
                records[window] = nil
            }
        }
    }

    /// 為一個視窗註冊「銷毀」與「標題改變」通知，並記下它現在的標題與文件位置。
    private func watch(_ window: AXUIElement, pid: pid_t, observer: AXObserver) {
        let values = window.values([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, "AXDocument"])
        guard values[kAXRoleAttribute] as? String == kAXWindowRole as String,
              values[kAXSubroleAttribute] as? String == kAXStandardWindowSubrole as String else {
            log.debug("略過非標準視窗（pid \(pid)）：\(String(describing: values[kAXSubroleAttribute]), privacy: .public)")
            return
        }
        let title = values[kAXTitleAttribute] as? String ?? ""
        let url = ClosedWindowPolicy.documentURL(from: values["AXDocument"])
        if let known = records[window] {
            // App 忙碌或逾時時這次可能讀不到：讀不到就保留舊值，不要用空值蓋掉已知的文件位置
            records[window]?.title = title.isEmpty ? known.title : title
            records[window]?.url = url ?? known.url
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon) == .success
        else { return }
        AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, refcon)
        records[window] = Record(pid: pid, title: title, url: url)
        log.debug("監看視窗（pid \(pid)）：有文件 \(url != nil)")
    }

    // MARK: - 通知（watcher 執行緒）

    private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon else { return }
        Unmanaged<ClosedWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            .handle(observer: observer, element: element, notification: notification as String)
    }

    private func handle(observer: AXObserver, element: AXUIElement, notification: String) {
        switch notification {
        case kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            watch(element, pid: pid, observer: observer)
        case kAXTitleChangedNotification:
            guard let record = records[element] else { return }
            // 存檔、另存新檔、換文件時標題會變；文件位置要一起重讀
            let values = element.values([kAXTitleAttribute, "AXDocument"])
            records[element] = Record(
                pid: record.pid,
                title: values[kAXTitleAttribute] as? String ?? record.title,
                url: ClosedWindowPolicy.documentURL(from: values["AXDocument"]) ?? record.url
            )
        case kAXUIElementDestroyedNotification:
            log.debug("視窗銷毀：已記錄 \(self.records[element] != nil)，有文件 \(self.records[element]?.url != nil)")
            guard let record = records.removeValue(forKey: element),
                  ClosedWindowPolicy.isRestorable(record.url), let url = record.url,
                  let bundleID = bundleIDs[record.pid] else { return }
            let closed = Closed(pid: record.pid, bundleID: bundleID, title: record.title, url: url, closedAt: Date())
            let onClosed = onClosed
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelay) {
                // App 在這段時間內結束了：是被一起關掉的，不算使用者關了視窗
                guard let app = NSRunningApplication(processIdentifier: closed.pid), !app.isTerminated else { return }
                onClosed(closed)
            }
        default:
            break
        }
    }
}
