//
//  ClosedWindowStoreTests.swift
//  DockLensTests
//
//  驗證「最近關閉」清單的純邏輯：什麼檔案收、同檔去重、容量上限、已開著或已刪除的不列、符號連結路徑視為同一個檔案。
//  偵測視窗被關掉（AXObserver）要真的 App 才測得到，由端到端自我測試涵蓋。
//

import Foundation
import Testing
@testable import DockLens

struct ClosedWindowStoreTests {
    private let notes = URL(fileURLWithPath: "/Users/me/Documents/notes.txt")
    private let todo = URL(fileURLWithPath: "/Users/me/Documents/todo.txt")

    private func makeEntry(_ bundleID: String, _ url: URL, at date: Date = Date()) -> ClosedWindowEntry {
        ClosedWindowEntry(bundleID: bundleID, title: url.lastPathComponent, url: url, closedAt: date)
    }

    /// 預設屬於 `app.a`
    private func makeEntry(_ url: URL, at date: Date = Date()) -> ClosedWindowEntry {
        makeEntry("app.a", url, at: date)
    }

    // MARK: - 收什麼

    @Test func onlyFileURLsAreRestorable() {
        #expect(ClosedWindowPolicy.isRestorable(URL(string: "file:///Users/me/a.txt")))
        // 瀏覽器視窗的 AXDocument 是網址（可能來自隱私視窗），不收
        #expect(!ClosedWindowPolicy.isRestorable(URL(string: "https://example.com/")))
        #expect(!ClosedWindowPolicy.isRestorable(URL(string: "chrome://newtab/")))
        #expect(!ClosedWindowPolicy.isRestorable(nil))
    }

    @Test func filesInTheTrashAreNotRestorable() {
        // 丟進垃圾桶後才關視窗：重開只會打開垃圾桶裡的檔案
        #expect(!ClosedWindowPolicy.isRestorable(URL(fileURLWithPath: "/Users/me/.Trash/old.txt")))
        #expect(ClosedWindowPolicy.isRestorable(URL(fileURLWithPath: "/Users/me/Documents/trash.txt")))
    }

    @Test func parsesDocumentValueFromAccessibilityAttribute() {
        #expect(ClosedWindowPolicy.documentURL(from: "file:///Users/me/a.txt" as CFString)?.path == "/Users/me/a.txt")
        #expect(ClosedWindowPolicy.documentURL(from: URL(fileURLWithPath: "/Users/me/a.txt") as CFURL)?.path == "/Users/me/a.txt")
        #expect(ClosedWindowPolicy.documentURL(from: "" as CFString) == nil)
        #expect(ClosedWindowPolicy.documentURL(from: nil) == nil)
    }

    // MARK: - 新增與去重

    @Test func newestFirst() {
        let store = ClosedWindowStore()
        store.add(makeEntry(notes))
        store.add(makeEntry(todo, at: Date().addingTimeInterval(10)))
        #expect(store.entries.map(\.url) == [todo, notes])
    }

    @Test func sameFileKeepsOnlyTheLatestEntry() {
        let store = ClosedWindowStore()
        let first = Date(timeIntervalSince1970: 1000)
        store.add(makeEntry(notes, at: first))
        // 一分鐘後又開了又關：舊的那筆被取代
        store.add(makeEntry(notes, at: first.addingTimeInterval(60)))
        #expect(store.entries.count == 1)
        #expect(store.entries[0].closedAt == first.addingTimeInterval(60))
    }

    @Test func differentAppsKeepTheirOwnEntriesForTheSameFile() {
        let store = ClosedWindowStore()
        store.add(makeEntry("app.a", notes))
        store.add(makeEntry("app.b", notes))
        #expect(store.entries.count == 2)
    }

    @Test func duplicateReportWithinAFewSecondsKeepsOneEntryButNotifiesOnce() {
        // 從面板按 X 會先記一筆（不通知），偵測機制稍後又報同一次關閉：清單不重複，但通知一次讓面板重新判斷
        let store = ClosedWindowStore()
        var notified = 0
        store.onAdd = { _ in notified += 1 }
        let now = Date()
        store.add(makeEntry(notes, at: now), notify: false)
        #expect(notified == 0)
        store.add(makeEntry(notes, at: now.addingTimeInterval(0.7)))
        #expect(store.entries.count == 1)
        #expect(store.entries[0].closedAt == now)
        #expect(notified == 1)
    }

    @Test func removeRecentDropsOnlyThatAppsFreshEntries() {
        // App 結束得慢，視窗一個個被銷毀而被誤記：結束後把這段時間內的紀錄清掉，更早的與別的 App 的不動
        let store = ClosedWindowStore()
        let now = Date(timeIntervalSince1970: 10_000)
        store.add(makeEntry("app.a", notes, at: now.addingTimeInterval(-60)))
        store.add(makeEntry("app.a", todo, at: now.addingTimeInterval(-1)))
        store.add(makeEntry("app.b", URL(fileURLWithPath: "/tmp/b.txt"), at: now.addingTimeInterval(-1)))
        store.removeRecent(bundleID: "app.a", within: 3, now: now)
        #expect(store.entries.map(\.url.lastPathComponent).sorted() == ["b.txt", "notes.txt"])
    }

    @Test func visibleSkipsOpenAndMissingFilesWithoutTouchingTheStore() {
        let candidates = [makeEntry(notes), makeEntry(todo)]
        let open: Set<String> = [ClosedWindowPolicy.key(notes)]
        #expect(ClosedWindowStore.visible(candidates, excludingOpen: open, limit: 4, exists: { _ in true }).map(\.url) == [todo])
        #expect(ClosedWindowStore.visible(candidates, excludingOpen: [], limit: 4, exists: { $0 == notes }).map(\.url) == [notes])
    }

    @Test func notifiesOnAdd() {
        let store = ClosedWindowStore()
        var added: [String] = []
        store.onAdd = { added.append($0.url.lastPathComponent) }
        store.add(makeEntry(notes))
        #expect(added == ["notes.txt"])
    }

    @Test func capacityDropsTheOldest() {
        let store = ClosedWindowStore()
        let base = Date(timeIntervalSince1970: 1000)
        for index in 0..<(ClosedWindowStore.capacity + 5) {
            store.add(makeEntry(URL(fileURLWithPath: "/tmp/file\(index).txt"), at: base.addingTimeInterval(Double(index) * 10)))
        }
        #expect(store.entries.count == ClosedWindowStore.capacity)
        #expect(store.entries.first?.url.lastPathComponent == "file\(ClosedWindowStore.capacity + 4).txt")
        #expect(!store.entries.contains { $0.url.lastPathComponent == "file0.txt" })
    }

    // MARK: - 面板要顯示哪些

    @Test func panelListsOnlyThisAppsEntries() {
        let store = ClosedWindowStore()
        store.add(makeEntry("app.a", notes))
        store.add(makeEntry("app.b", todo))
        #expect(store.entries(for: "app.a", exists: { _ in true }).map(\.url) == [notes])
    }

    @Test func panelSkipsDocumentsThatAreOpenAgain() {
        let store = ClosedWindowStore()
        store.add(makeEntry(notes))
        store.add(makeEntry(todo))
        let open: Set<String> = [ClosedWindowPolicy.key(notes)]
        #expect(store.entries(for: "app.a", excludingOpen: open, exists: { _ in true }).map(\.url) == [todo])
    }

    @Test func panelSkipsDeletedFiles() {
        let store = ClosedWindowStore()
        store.add(makeEntry(notes))
        store.add(makeEntry(todo))
        #expect(store.entries(for: "app.a", exists: { $0 == todo }).map(\.url) == [todo])
    }

    @Test func panelLimitsHowManyAreShown() {
        let store = ClosedWindowStore()
        for index in 0..<10 { store.add(makeEntry(URL(fileURLWithPath: "/tmp/f\(index).txt"))) }
        #expect(store.entries(for: "app.a", exists: { _ in true }).count == ClosedWindowStore.panelLimit)
        #expect(store.entries(for: "app.a", limit: 2, exists: { _ in true }).count == 2)
    }

    @Test func removeAndRemoveAll() {
        let store = ClosedWindowStore()
        store.add(makeEntry(notes))
        store.add(makeEntry(todo))
        store.remove(store.entries[0].id)
        #expect(store.entries.count == 1)
        store.removeAll()
        #expect(store.entries.isEmpty)
    }

    // MARK: - 比對檔案

    @Test func symlinkedPathsAreTheSameDocument() {
        // /tmp 是 /private/tmp 的符號連結：視窗列舉與紀錄各自拿到的寫法可能不同
        #expect(ClosedWindowPolicy.key(URL(fileURLWithPath: "/tmp/x.txt")) == ClosedWindowPolicy.key(URL(fileURLWithPath: "/private/tmp/x.txt")))
        #expect(ClosedWindowPolicy.key(URL(fileURLWithPath: "/tmp/a/../x.txt")) == ClosedWindowPolicy.key(URL(fileURLWithPath: "/tmp/x.txt")))
    }

    // MARK: - 顯示名稱

    @Test func displayNameUsesFileNameAndParentFolder() {
        let item = makeEntry(notes)
        #expect(item.displayName == "notes.txt")
        #expect(item.parentName == "Documents")
        // 視窗標題常帶「— 已編輯」之類的後綴，清單用檔名才穩定
        #expect(ClosedWindowEntry(bundleID: "a", title: "notes.txt — 已編輯", url: notes).displayName == "notes.txt")
    }

    @Test func rootFolderHasNoParentName() {
        let item = makeEntry(URL(fileURLWithPath: "/Applications"))
        #expect(item.parentName == "")
    }
}
