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
        s = s.replacingOccurrences(of: "^[，,。、\\s]+", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip the decorations a language model likes to add around its answer.
    static func postProcess(_ output: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = ["整理後：", "整理後的文字：", "結果：", "輸出：", "Result:", "Output:"]
        for l in labels where s.hasPrefix(l) { s = String(s.dropFirst(l.count)).trimmingCharacters(in: .whitespaces) }
        let pairs: [(String, String)] = [("「", "」"), ("“", "”"), ("\"", "\""), ("『", "』")]
        for (o, c) in pairs where s.hasPrefix(o) && s.hasSuffix(c) && s.count > 2 && !s.dropFirst().dropLast().contains(c) {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Add a space when pasting right after existing text that does not end with whitespace.
    static func joiner(previousChar: Character?, next: String) -> String {
        guard let p = previousChar, !p.isWhitespace, !p.isNewline, let n = next.first else { return "" }
        if p.isLetter && p.isASCII && n.isLetter && n.isASCII { return " " }
        return ""
    }
}
