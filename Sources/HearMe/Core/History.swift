import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var app: String?
    var mode: String
    var tone: String
    var raw: String
    var output: String
    var audioSeconds: Double
    var transcribeSeconds: Double
    var polishSeconds: Double
}

/// Append-only JSONL on disk, kept on this machine only (matches "on-device history").
final class History {
    static let shared = History()
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HearMe", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("history.jsonl")
        }
    }

    func append(_ e: HistoryEntry) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard var data = try? enc.encode(e) else { return }
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func recent(_ n: Int) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").suffix(n).reversed().compactMap { line in
            try? dec.decode(HistoryEntry.self, from: Data(line.utf8))
        }
    }
}
