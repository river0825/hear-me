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
