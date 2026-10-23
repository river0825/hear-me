import XCTest
@testable import HearMe

final class PushToTalkTests: XCTestCase {
    func testHoldToTalk() {
        var m = PushToTalkMachine()
        XCTAssertEqual(m.press(at: 0), .start)
        XCTAssertEqual(m.release(at: 1.2), .stop)
        XCTAssertFalse(m.recording)
    }

    func testTapLatchesUntilNextTap() {
        var m = PushToTalkMachine()
        XCTAssertEqual(m.press(at: 0), .start)
        XCTAssertEqual(m.release(at: 0.1), .none)   // quick tap → keep listening
        XCTAssertTrue(m.recording)
        XCTAssertEqual(m.press(at: 3.0), .stop)     // next tap stops
        XCTAssertEqual(m.release(at: 3.1), .none)
        XCTAssertFalse(m.recording)
    }

    func testPressWhileRecordingIsIgnored() {
        var m = PushToTalkMachine()
        _ = m.press(at: 0)
        XCTAssertEqual(m.press(at: 0.5), .none)
        XCTAssertEqual(m.release(at: 2), .stop)
    }

    func testResetClearsLatch() {
        var m = PushToTalkMachine()
        _ = m.press(at: 0); _ = m.release(at: 0.1)
        m.reset()
        XCTAssertEqual(m.press(at: 5), .start)
    }
}

final class TextRulesTests: XCTestCase {
    func testChineseFillersRemoved() {
        XCTAssertEqual(TextRules.basicCleanup("嗯 我明天 呃 要開會"), "我明天 要開會")
        XCTAssertEqual(TextRules.basicCleanup("嗯，那我們開始。"), "那我們開始。")
        XCTAssertEqual(TextRules.basicCleanup("好，嗯，就這樣"), "好，就這樣")
    }

    func testSpaceBeforeFullWidthPunctuationRemoved() {
        XCTAssertEqual(TextRules.basicCleanup("個人字典的狀況會是怎麼樣 ？我看一下。"), "個人字典的狀況會是怎麼樣？我看一下。")
        XCTAssertEqual(TextRules.basicCleanup("測試一下新的功能 ，看可不可以使用。"), "測試一下新的功能，看可不可以使用。")
        XCTAssertEqual(TextRules.basicCleanup("ship it, then fix the crash"), "ship it, then fix the crash")
    }

    func testChineseFillerInsideWordIsKept() {
        // 「嗯」 inside a real word must survive.
        XCTAssertEqual(TextRules.basicCleanup("這個字念嗯嗯"), "這個字念嗯嗯")
    }

    func testEnglishFillersRemoved() {
        XCTAssertEqual(TextRules.basicCleanup("um, so I think, uh, we should ship it"), "so I think, we should ship it")
        XCTAssertEqual(TextRules.basicCleanup("album umbrella"), "album umbrella")
    }

    func testPostProcessStripsQuotesAndLabels() {
        XCTAssertEqual(TextRules.postProcess("整理後：「明天四點開會。」"), "明天四點開會。")
        XCTAssertEqual(TextRules.postProcess("\"Ship it.\""), "Ship it.")
        XCTAssertEqual(TextRules.postProcess("他說「好」，然後走了。"), "他說「好」，然後走了。")
    }

    func testPostProcessDropsEchoedInstructions() {
        let out = TextRules.postProcess("請協助匯出記錄。  \n以前辨識錯過、使用者更正過的寫法：登入業→登入頁。相同者請改。")
        XCTAssertEqual(out, "請協助匯出記錄。")
    }

    func testJoiner() {
        XCTAssertEqual(TextRules.joiner(previousChar: "a", next: "hello"), " ")
        XCTAssertEqual(TextRules.joiner(previousChar: "。", next: "明天"), "")
        XCTAssertEqual(TextRules.joiner(previousChar: " ", next: "x"), "")
        XCTAssertEqual(TextRules.joiner(previousChar: nil, next: "x"), "")
    }
}

final class ToneResolverTests: XCTestCase {
    let rules = [
        AppToneRule(bundleId: "com.apple.mail", tone: .formal),
        AppToneRule(bundleId: "com.microsoft.", tone: .formal),
        AppToneRule(bundleId: "com.apple.Terminal", tone: .verbatim),
    ]

    func testExactMatchCaseInsensitive() {
        XCTAssertEqual(ToneResolver.tone(forBundleId: "com.apple.Mail", rules: rules, fallback: .general), .formal)
    }
    func testPrefixRule() {
        XCTAssertEqual(ToneResolver.tone(forBundleId: "com.microsoft.Outlook", rules: rules, fallback: .general), .formal)
    }
    func testFallback() {
        XCTAssertEqual(ToneResolver.tone(forBundleId: "com.apple.Notes", rules: rules, fallback: .casual), .casual)
        XCTAssertEqual(ToneResolver.tone(forBundleId: nil, rules: rules, fallback: .casual), .casual)
    }
}

final class HistoryTests: XCTestCase {
    func testAppendAndRecent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hearme-test-\(UUID()).jsonl")
        let h = History(url: url)
        for i in 1...3 {
            h.append(HistoryEntry(date: Date(), app: "com.apple.Notes", mode: "dictate", tone: "general", raw: "raw \(i)", output: "out \(i)", audioSeconds: 1, transcribeSeconds: 0.2, polishSeconds: 1.5))
        }
        let recent = h.recent(2)
        XCTAssertEqual(recent.map(\.output), ["out 3", "out 2"])
        try? FileManager.default.removeItem(at: url)
    }
}

final class PolishGuardTests: XCTestCase {
    func testAnswerIsRejected() {
        XCTAssertTrue(Polisher.looksLikeAnswerNotCleanup(raw: "這首歌的背景是什麼", output: "這首歌的背景是關於一個人對自己過去的回憶，以及對未來的期望。"))
    }
    func testCleanupsAreAccepted() {
        XCTAssertFalse(Polisher.looksLikeAnswerNotCleanup(raw: "欸 這首歌的背景是什麼", output: "這首歌的背景是什麼？"))
        XCTAssertFalse(Polisher.looksLikeAnswerNotCleanup(raw: "嗯 我明天 呃 明天下午三點 不對 四點 要跟客戶開會 你幫我記一下", output: "我明天下午四點要跟客戶開會，你幫我記一下。"))
        XCTAssertFalse(Polisher.looksLikeAnswerNotCleanup(raw: "這次發版要做三件事第一更新登入頁第二修掉那個那個閃退的問題第三寫 release notes", output: "這次發版要做三件事：\n1. 更新登入頁\n2. 修掉閃退的問題\n3. 寫 release notes"))
        XCTAssertFalse(Polisher.looksLikeAnswerNotCleanup(raw: "um so I think we should, uh, ship the login page first and then, you know, fix the crash", output: "I think we should ship the login page first and then fix the crash."))
    }
}

final class PolisherPromptTests: XCTestCase {
    func testPromptMentionsDictionaryAndTone() {
        let r = PolishRequest(raw: "x", tone: .formal, outputLanguage: .english, dictionary: ["IronNote", "拆招"], appName: "Mail", speechLocale: "zh_TW")
        let p = Polisher.instructions(for: r)
        XCTAssertTrue(p.contains("IronNote、拆招"))
        XCTAssertTrue(p.contains("正式"))
        XCTAssertTrue(p.contains("English"))
        XCTAssertTrue(p.contains("「Mail」"))
    }
}

final class CorrectionTests: XCTestCase {
    func testApplyLongestFirstAndSafety() {
        let cs = [
            Correction(wrong: "登入業", right: "登入頁"),
            Correction(wrong: "登入業面", right: "登入畫面"),
            Correction(wrong: "業", right: "頁"),            // unsafe single char: ignored
            Correction(wrong: "Irannote", right: "IronNote"),
        ]
        let (out, used) = CorrectionRules.apply("更新登入業面和登入業，匯出 Irannote 的作業", corrections: cs)
        XCTAssertEqual(out, "更新登入畫面和登入頁，匯出 IronNote 的作業")
        XCTAssertEqual(used.count, 3)
    }

    func testDiffExtractsReplacementWithContext() {
        let reps = TextDiff.replacements(old: "這次發版要做三件事第一更新登入業第二修掉閃退", new: "這次發版要做三件事第一更新登入頁第二修掉閃退")
        XCTAssertEqual(reps, [TextDiff.Replacement(wrong: "登入業", right: "登入頁")])
    }

    func testDiffMultipleAndAscii() {
        let reps = TextDiff.replacements(old: "請把 Irannote 的記錄繪出", new: "請把 IronNote 的記錄匯出")
        XCTAssertEqual(reps.map(\.wrong), ["Irannote", "記錄繪"])
        XCTAssertEqual(reps.map(\.right), ["IronNote", "記錄匯"])
    }

    func testDiffIgnoresPureInsertOrDelete() {
        XCTAssertEqual(TextDiff.replacements(old: "明天開會", new: "明天下午開會"), [])
        XCTAssertEqual(TextDiff.replacements(old: "嗯明天開會", new: "明天開會"), [])
    }

    func testStoreLearnMergesAndRejects() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hearme-corr-\(UUID()).json")
        let s = CorrectionStore(url: url)
        XCTAssertTrue(s.learn(wrong: "繪出", right: "匯出"))
        XCTAssertTrue(s.learn(wrong: "繪出", right: "匯出"))
        XCTAssertFalse(s.learn(wrong: "業", right: "頁"))
        XCTAssertFalse(s.learn(wrong: "匯出", right: "匯出"))
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items[0].count, 2)
        let reloaded = CorrectionStore(url: url)
        XCTAssertEqual(reloaded.items.map(\.wrong), ["繪出"])
        try? FileManager.default.removeItem(at: url)
    }
}


final class LanguagePickTests: XCTestCase {
    func testScriptMatch() {
        XCTAssertEqual(Transcriber.scriptMatch("這次發版要做三件事", localeId: "zh_TW"), 1.0, accuracy: 0.01)
        XCTAssertEqual(Transcriber.scriptMatch("I think we should ship it", localeId: "zh_TW"), 0.0, accuracy: 0.01)
        XCTAssertEqual(Transcriber.scriptMatch("I think we should ship it", localeId: "en_US"), 1.0, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(Transcriber.scriptMatch("第三寫 release notes", localeId: "zh_TW"), 0.2)
        XCTAssertEqual(Transcriber.scriptMatch("3:00, 4:00", localeId: "zh_TW"), 0.0)
    }

    func testEnglishSpeechUnderChinesePrimaryPicksEnglish() {
        XCTAssertEqual(Transcriber.chooseIndex([
            ("zh_TW", "I'm so I think we should ship the logan page", 0.87),
            ("en_US", "So I think we should ship the login page", 0.84),
        ]), 1)
        XCTAssertEqual(Transcriber.chooseIndex([
            ("zh_TW", "Pregenarate a new I can't for this app", 0.80),
            ("en_US", "Please generate a new icon for this app", 0.90),
        ]), 1)
    }

    func testChineseSpeechKeepsChineseEvenWhenEnglishModelIsConfident() {
        // CEO 10-23: 「直接把它變成公開的 repo」 came out as the English model's "So the champions and Gong Kai, the repo."
        XCTAssertEqual(Transcriber.chooseIndex([
            ("zh_TW", "直接把它變成公開的 repo", 0.70),
            ("en_US", "So the champions and Gong Kai, the repo.", 0.95),
        ]), 0)
        XCTAssertEqual(Transcriber.chooseIndex([
            ("zh_TW", "請幫我把 Irannote 的訓練記錄匯出", 0.92),
            ("en_US", "Qing bang wo by Iran node", 0.25),
        ]), 0)
        // Primary empty, secondary confident → secondary.
        XCTAssertEqual(Transcriber.chooseIndex([("zh_TW", "", 0), ("en_US", "Hello there", 0.9)]), 1)
    }
}


final class DevVocabularyTests: XCTestCase {
    func testRepairsMisspelledDevWords() {
        let (out, fixes) = TextRules.repairAsciiWords("第三寫 realeasenotes 然後 push 到 repo，順便改一下 icone", terms: DevVocabulary.terms)
        XCTAssertEqual(out, "第三寫 release notes 然後 push 到 repo，順便改一下 icon")
        XCTAssertEqual(fixes.map(\.0), ["realeasenotes", "icone"])
    }

    func testDictionaryTermsGetFuzzyRepairToo() {
        let (out, _) = TextRules.repairAsciiWords("請把 Irannote 的記錄匯出到 github", terms: DevVocabulary.terms + ["IronNote"])
        XCTAssertEqual(out, "請把 IronNote 的記錄匯出到 GitHub")
    }

    func testKeepsInflectionsAndShortWords() {
        let (out, fixes) = TextRules.repairAsciiWords("icons 和 commits 都 ok，fix 了 bugs", terms: DevVocabulary.terms)
        XCTAssertEqual(out, "icons 和 commits 都 ok，fix 了 bugs")
        XCTAssertTrue(fixes.isEmpty)
    }

    func testSpacing() {
        XCTAssertEqual(TextRules.spaceBetweenHanAndLatin("寫release notes然後push到main"), "寫 release notes 然後 push 到 main")
        XCTAssertEqual(TextRules.spaceBetweenHanAndLatin("下午 3:00 開會。"), "下午 3:00 開會。")
        XCTAssertEqual(TextRules.spaceBetweenHanAndLatin("已經是 GitHub 了"), "已經是 GitHub 了")
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionParseAndCompare() {
        XCTAssertEqual(AppVersion("v0.1.7")!.parts, [0, 1, 7])
        XCTAssertEqual(AppVersion("1.2")!.description, "1.2")
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion(""))
        XCTAssertTrue(AppVersion("0.1.6")! < AppVersion("v0.1.7")!)
        XCTAssertTrue(AppVersion("0.1.9")! < AppVersion("0.2")!)
        XCTAssertFalse(AppVersion("0.2.0")! < AppVersion("0.2")!)
        XCTAssertTrue(AppVersion("0.2.0")! == AppVersion("0.2")!)
        XCTAssertTrue(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
    }

    func testParseLatestRelease() throws {
        let json = """
        {"tag_name":"v0.1.7","html_url":"https://github.com/river0825/hear-me/releases/tag/v0.1.7",
         "assets":[{"name":"HearMe.zip.sha256","browser_download_url":"https://x/HearMe.zip.sha256"},
                   {"name":"HearMe.zip","browser_download_url":"https://x/HearMe.zip"}]}
        """
        let r = try ReleaseInfo.parse(Data(json.utf8))
        XCTAssertEqual(r.tag, "v0.1.7")
        XCTAssertEqual(r.version, AppVersion("0.1.7")!)
        XCTAssertEqual(r.zipURL.absoluteString, "https://x/HearMe.zip")
        XCTAssertEqual(r.shaURL?.absoluteString, "https://x/HearMe.zip.sha256")
        XCTAssertEqual(r.pageURL.absoluteString, "https://github.com/river0825/hear-me/releases/tag/v0.1.7")
        XCTAssertThrowsError(try ReleaseInfo.parse(Data(#"{"tag_name":"v1.0.0","assets":[]}"#.utf8)))
        XCTAssertThrowsError(try ReleaseInfo.parse(Data(#"{"message":"Not Found"}"#.utf8)))
    }

    func testSha256Parsing() throws {
        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(try Updater.parseSha256("\(hex.uppercased())  build/HearMe.zip\n"), hex)
        XCTAssertThrowsError(try Updater.parseSha256("not a hash  HearMe.zip"))
        XCTAssertEqual(Updater.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
