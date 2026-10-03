//
//  LocalizationTests.swift
//  DockLensTests
//
//  驗證多國語系的建置結果：每種語言（含來源語言繁中）都真的編出字串表，
//  並且取字串時不會落到別的語言。
//  為什麼需要：v1.0.7 的 xcstrings 沒有明確寫出來源語言 zh-Hant 的值，建置時不會輸出
//  zh-Hant 的字串表，繁中使用者的查詢退回開發語言 en，整個介面變成英文，而其他測試完全沒有察覺。
//

import Foundation
import Testing
@testable import DockLens

struct LocalizationTests {
    /// 預期支援的語言（新增語言時要同步更新）
    nonisolated static let expectedLanguages = [
        "ar", "ca", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko",
        "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    /// 找出某語言的資源資料夾；不存在就是該語言沒被編進 App。
    private func bundle(for language: String) -> Bundle? {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    @Test(arguments: expectedLanguages)
    func everyLanguageHasItsOwnStringTable(language: String) throws {
        let languageBundle = try #require(bundle(for: language), "\(language).lproj 沒有被編進 App")
        // 以該語言的資源查詢，不經過系統語言偏好；表不存在時 value 會是我們給的標記
        let marker = "‹missing›"
        let value = languageBundle.localizedString(forKey: "歡迎使用 DockLens", value: marker, table: nil)
        #expect(value != marker, "\(language) 沒有字串表（使用者會看到別的語言）")
    }

    @Test(arguments: expectedLanguages)
    func recentlyClosedStringsAreTranslated(language: String) throws {
        // 「最近關閉」功能的三條新字串：每種語言都要有譯文，且英文版不能還是中文
        let languageBundle = try #require(bundle(for: language))
        let marker = "‹missing›"
        for key in ["最近關閉", "記住最近關閉的文件視窗", "在該 App 的預覽上一鍵重開。只存在記憶體，結束 DockLens 就清空。"] {
            let value = languageBundle.localizedString(forKey: key, value: marker, table: nil)
            #expect(value != marker, "\(language) 缺少「\(key)」的翻譯")
            if language == "en" { #expect(value != key, "en 還是中文：\(key)") }
        }
    }

    @Test func traditionalChineseShowsChineseNotEnglish() throws {
        let zh = try #require(bundle(for: "zh-Hant"))
        #expect(zh.localizedString(forKey: "歡迎使用 DockLens", value: nil, table: nil) == "歡迎使用 DockLens")
        let en = try #require(bundle(for: "en"))
        #expect(en.localizedString(forKey: "歡迎使用 DockLens", value: nil, table: nil) == "Welcome to DockLens")
    }

    @Test func pluralKeyHasAllCategoriesPerLanguage() throws {
        // 複數字串在編譯後放在 .stringsdict；俄文、阿拉伯文等類別多的語言不能只剩 other
        let russian = try #require(bundle(for: "ru"))
        let path = try #require(russian.path(forResource: "Localizable", ofType: "stringsdict"))
        let dict = try #require(NSDictionary(contentsOfFile: path))
        let entry = try #require(dict["還有 %lld 個行程"] as? [String: Any])
        let variable = try #require(entry["value"] as? [String: Any])
        for category in ["one", "few", "many", "other"] {
            #expect(variable[category] != nil, "ru 缺少複數類別 \(category)")
        }
    }

    @Test func durationFormattingFollowsRequestedLocale() {
        // 時間長度交給系統格式化，不能再退回只對中文正確的手拼字串
        let english = Duration.seconds(80 * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(Locale(identifier: "en_US")))
        #expect(english.contains("hr") && english.contains("min"))
        #expect(!english.contains("小時"))
    }
}
