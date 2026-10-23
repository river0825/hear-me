import Foundation

/// One learned correction: the recognizer wrote `wrong`, the user meant `right`.
struct Correction: Codable, Identifiable, Equatable {
    var id = UUID()
    var wrong: String
    var right: String
    var count: Int = 1
    var date: Date = Date()
}

/// Pure helpers so the behaviour is unit-testable.
enum CorrectionRules {
    /// Single CJK characters or very short ASCII fragments are too dangerous to replace globally.
    static func isSafe(wrong: String) -> Bool {
        let w = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return false }
        let ascii = w.allSatisfy { $0.isASCII }
        return ascii ? w.count >= 3 : w.count >= 2
    }

    /// Longest `wrong` first so "登入業面" wins over "登入業". Exact, case-sensitive replacement.
    static func apply(_ text: String, corrections: [Correction]) -> (String, [Correction]) {
        var out = text
        var used: [Correction] = []
        for c in corrections.sorted(by: { $0.wrong.count > $1.wrong.count }) {
            guard isSafe(wrong: c.wrong), c.wrong != c.right, out.contains(c.wrong) else { continue }
            out = out.replacingOccurrences(of: c.wrong, with: c.right)
            used.append(c)
        }
        return (out, used)
    }
}

/// Character-level diff that turns "what was pasted" vs "what the user fixed it to" into corrections.
enum TextDiff {
    struct Replacement: Equatable { var wrong: String; var right: String }

    static func replacements(old: String, new: String, maxLength: Int = 600) -> [Replacement] {
        let a = Array(old), b = Array(new)
        guard !a.isEmpty, !b.isEmpty, a.count <= maxLength, b.count <= maxLength, a != b else { return [] }
        // LCS table
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        // Walk: collect runs of (deleted, inserted) between common characters.
        var i = 0, j = 0
        var runs: [(delStart: Int, delEnd: Int, insStart: Int, insEnd: Int)] = []
        var cur: (Int, Int, Int, Int)? = nil
        func closeRun() { if let c = cur { runs.append((c.0, c.1, c.2, c.3)); cur = nil } }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                closeRun(); i += 1; j += 1
            } else if j < b.count, i >= a.count || dp[i][j + 1] >= dp[i + 1][j] {
                if cur == nil { cur = (i, i, j, j) }
                cur!.3 = j + 1; j += 1
            } else {
                if cur == nil { cur = (i, i, j, j) }
                cur!.1 = i + 1; i += 1
            }
        }
        closeRun()
        func isWordChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        // 1. Only keep real replacements (both sides non-empty), expand ASCII runs to whole words.
        var spans: [(ds: Int, de: Int, iS: Int, ie: Int)] = []
        for r in runs {
            var ds = r.delStart, de = r.delEnd, iS = r.insStart, ie = r.insEnd
            guard de > ds, ie > iS else { continue }          // pure insert/delete: not a recognition error
            let touchesWord = isWordChar(a[ds]) || isWordChar(a[de - 1]) || (ds > 0 && isWordChar(a[ds - 1])) || (de < a.count && isWordChar(a[de]))
            if touchesWord {
                while ds > 0, iS > 0, isWordChar(a[ds - 1]), a[ds - 1] == b[iS - 1] { ds -= 1; iS -= 1 }
                while de < a.count, ie < b.count, isWordChar(a[de]), a[de] == b[ie] { de += 1; ie += 1 }
            }
            spans.append((ds, de, iS, ie))
        }
        // 2. Merge spans that now touch or overlap (two edits inside one word).
        spans.sort { $0.ds < $1.ds }
        var merged: [(ds: Int, de: Int, iS: Int, ie: Int)] = []
        for sp in spans {
            if let last = merged.last, sp.ds <= last.de {
                merged[merged.count - 1] = (last.ds, max(last.de, sp.de), last.iS, max(last.ie, sp.ie))
            } else {
                merged.append(sp)
            }
        }
        // 3. Pad CJK fragments with context, left first, until they are specific enough to replace globally.
        var out: [Replacement] = []
        for sp in merged {
            var ds = sp.ds, de = sp.de, iS = sp.iS, ie = sp.ie
            let isAscii = a[ds..<de].allSatisfy { $0.isASCII }
            let target = isAscii ? 3 : 3
            var guardCount = 0
            while de - ds < target, guardCount < 6 {
                if ds > 0, iS > 0, a[ds - 1] == b[iS - 1] { ds -= 1; iS -= 1 }
                else if de < a.count, ie < b.count, a[de] == b[ie] { de += 1; ie += 1 }
                else { break }
                guardCount += 1
            }
            let wrong = String(a[ds..<de]), right = String(b[iS..<ie])
            if CorrectionRules.isSafe(wrong: wrong), wrong != right, wrong.count <= 30, right.count <= 30 {
                out.append(Replacement(wrong: wrong, right: right))
            }
        }
        return out
    }
}

/// Persistent store, JSON on disk next to the history file.
final class CorrectionStore: ObservableObject {
    static let shared = CorrectionStore()
    @Published private(set) var items: [Correction] = []
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HearMe", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("corrections.json")
        }
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        items = (try? dec.decode([Correction].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(items).write(to: url)
    }

    /// Returns false when the pair is rejected as unsafe.
    @discardableResult
    func learn(wrong: String, right: String) -> Bool {
        let w = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CorrectionRules.isSafe(wrong: w), !r.isEmpty, w != r else { return false }
        if let i = items.firstIndex(where: { $0.wrong == w }) {
            items[i].right = r; items[i].count += 1; items[i].date = Date()
        } else {
            items.append(Correction(wrong: w, right: r))
        }
        save()
        return true
    }

    func remove(id: UUID) { items.removeAll { $0.id == id }; save() }

    func apply(_ text: String) -> (String, [Correction]) { CorrectionRules.apply(text, corrections: items) }

    /// Words worth biasing the recognizer toward.
    var rightSides: [String] { Array(Set(items.map(\.right))) }
}
