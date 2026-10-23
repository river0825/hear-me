import Foundation

/// Rule-based text handling that does not need a language model.
enum TextRules {
    static let zhFillers = ["嗯", "呃", "欸", "齁", "蛤"]
    static let enFillers = ["um", "uh", "uhm", "erm", "hmm", "you know", "I mean"]

    /// Minimal cleanup used in verbatim mode or when no language model is available.
    static func basicCleanup(_ raw: String) -> String {
        var s = raw
        for f in enFillers {
            let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: f) + "(?![A-Za-z])[,，]?\\s*"
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        for f in zhFillers {
            // Chinese fillers show up standalone, often followed by punctuation or a space.
            s = s.replacingOccurrences(of: "(?<![\\p{Han}])" + f + "+[，,。、\\s]*", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "[，,、]" + f + "+(?=[，,。、\\s]|$)", with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        // The recognizer writes "功能 ，看" — no space belongs before or after full-width punctuation.
        s = s.replacingOccurrences(of: "\\s+(?=[，。、？！：；」』）])", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<=[，。、？！：；「『（])\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[，,。、\\s]+", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip the decorations a language model likes to add around its answer.
    static func postProcess(_ output: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = ["整理後：", "整理後的文字：", "結果：", "輸出：", "Result:", "Output:"]
        for l in labels where s.hasPrefix(l) { s = String(s.dropFirst(l.count)).trimmingCharacters(in: .whitespaces) }
        // Small on-device models sometimes echo an instruction line back; drop those lines.
        let echoMarkers = ["以前辨識錯過", "使用者更正過", "個人字典：", "Past recognition errors", "Personal dictionary:", "只輸出整理後"]
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in !echoMarkers.contains { line.contains($0) } }
            .joined(separator: "\n")
        let pairs: [(String, String)] = [("「", "」"), ("“", "”"), ("\"", "\""), ("『", "』")]
        for (o, c) in pairs where s.hasPrefix(o) && s.hasSuffix(c) && s.count > 2 && !s.dropFirst().dropLast().contains(c) {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 盤古之白: a space between Han characters and Latin letters/digits, the way Taiwanese developers write.
    static func spaceBetweenHanAndLatin(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "(?<=\\p{Han})(?=[A-Za-z0-9])", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<=[A-Za-z0-9])(?=\\p{Han})", with: " ", options: .regularExpression)
        return s
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Repair misspelled ASCII words against the user's dictionary and the built-in developer vocabulary:
    /// "realeasenotes" → "release notes", "icone" → "icon", "Irannote" → "IronNote", "github" → "GitHub".
    /// Conservative: words shorter than 4 letters are left alone, inflections (icons, commits) are kept,
    /// and the allowed edit distance grows slowly with length.
    static func repairAsciiWords(_ text: String, terms: [String]) -> (String, [(String, String)]) {
        let canonical = terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 && $0.allSatisfy { $0.isASCII } }
        guard !canonical.isEmpty else { return (text, []) }
        struct Term { let display: String; let key: [Character] }
        let table = canonical.map { Term(display: $0, key: Array($0.lowercased().filter { $0 != " " && $0 != "-" })) }
        var replacements: [(String, String)] = []
        let regex = try! NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9'\\-]*")
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range)
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            let key = Array(word.lowercased())
            var best: Term? = nil
            var bestDist = Int.max
            if word.count >= 4 {
                for t in table where t.key.count >= 3 {
                    let allowed = t.key.count <= 4 ? 1 : (t.key.count <= 7 ? 1 : 2)
                    let d = levenshtein(key, t.key)
                    if d <= allowed && d < bestDist { best = t; bestDist = d }
                }
            } else if let exact = table.first(where: { $0.key == key }) {
                best = exact; bestDist = 0   // short word, exact letters: only fix capitalisation (iOS, API, PR)
            }
            var replacement = word
            if let best {
                let display = best.display
                let isInflection = key != best.key && (key == best.key + ["s"] || key == best.key + ["e", "s"] || key == best.key + ["e", "d"] || key == best.key + ["i", "n", "g"])
                if bestDist == 0 {
                    if word != display && display.contains(where: { $0.isUppercase }) { replacement = display }
                } else if !isInflection {
                    replacement = display
                }
            }
            if replacement != word { replacements.append((word, replacement)) }
            out += replacement
        }
        out += ns.substring(from: last)
        return (out, replacements)
    }

    /// Add a space when pasting right after existing text that does not end with whitespace.
    static func joiner(previousChar: Character?, next: String) -> String {
        guard let p = previousChar, !p.isWhitespace, !p.isNewline, let n = next.first else { return "" }
        if p.isLetter && p.isASCII && n.isLetter && n.isASCII { return " " }
        return ""
    }
}
