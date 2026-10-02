//
//  PanelShortcutTests.swift
//  DockLensTests
//
//  驗證單鍵快捷鍵的判斷：四個字母（含大寫）對應正確動作，帶 ⌘／⌃／⌥ 的組合鍵與其他字元一律放行。
//

import CoreGraphics
import Testing
@testable import DockLens

struct PanelShortcutTests {
    @Test(arguments: [("w", PanelShortcut.close), ("m", .minimize), ("h", .hide), ("q", .quit), ("W", .close)])
    func lettersMapToShortcuts(characters: String, expected: PanelShortcut) {
        #expect(PanelShortcut.match(characters: characters, flags: []) == expected)
    }

    @Test func shiftIsAllowed() {
        #expect(PanelShortcut.match(characters: "w", flags: .maskShift) == .close)
    }

    /// ⌘W、⌘Q、⌃H、⌥M 是前景 App 或系統的快捷鍵，不能攔
    @Test(arguments: [CGEventFlags.maskCommand, .maskControl, .maskAlternate])
    func modifiedKeysPassThrough(flags: CGEventFlags) {
        #expect(PanelShortcut.match(characters: "w", flags: flags) == nil)
    }

    @Test(arguments: ["a", "", "wq", " ", "ㄊ"])
    func otherCharactersPassThrough(characters: String) {
        #expect(PanelShortcut.match(characters: characters, flags: []) == nil)
    }

    @Test func missingCharactersPassThrough() {
        #expect(PanelShortcut.match(characters: nil, flags: []) == nil)
    }
}
