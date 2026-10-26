import CryptoKit
import Foundation
import Security

/// Self-contained updater: asks GitHub for the latest Release, downloads the zip the Release
/// workflow published, checks it against the sha256 the same workflow wrote, requires the new
/// bundle to satisfy the *running* app's designated requirement (same identifier + same signing
/// certificate, so a tampered or foreign build is refused), swaps the bundle in place and relaunches.
/// The only network traffic is to GitHub; no user data is sent (CEO approved 2026-10-23).
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let nums = t.split(separator: ".").map { Int($0.prefix { $0.isNumber }) }
        guard !nums.isEmpty, nums.allSatisfy({ $0 != nil }) else { return nil }
        parts = nums.map { $0! }
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
    var description: String { parts.map(String.init).joined(separator: ".") }
}

struct ReleaseInfo: Equatable {
    let tag: String
    let version: AppVersion
    let zipURL: URL
    let shaURL: URL?
    let pageURL: URL

    static func == (a: ReleaseInfo, b: ReleaseInfo) -> Bool { a.tag == b.tag && a.zipURL == b.zipURL }

    /// Parse GitHub's `GET /repos/{owner}/{repo}/releases/latest` body.
    static func parse(_ data: Data, zipName: String = "HearMe.zip") throws -> ReleaseInfo {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { throw UpdateError.badResponse }
        guard let version = AppVersion(tag) else { throw UpdateError.badResponse }
        let assets = (obj["assets"] as? [[String: Any]]) ?? []
        func url(named name: String) -> URL? {
            assets.first { ($0["name"] as? String) == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
        }
        guard let zip = url(named: zipName) else { throw UpdateError.noAsset(zipName) }
        let page = (obj["html_url"] as? String).flatMap(URL.init) ?? URL(string: "https://github.com/\(Updater.repo)/releases")!
        return ReleaseInfo(tag: tag, version: version, zipURL: zip, shaURL: url(named: zipName + ".sha256"), pageURL: page)
    }
}

enum UpdateError: LocalizedError {
    case badResponse, noAsset(String), http(Int), checksumMismatch, noAppInZip
    case signature(String), notAnAppBundle, translocated, notWritable(String), tool(String, String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "GitHub 回應看不懂"
        case .noAsset(let n): return "Release 裡沒有 \(n)"
        case .http(let c): return "GitHub 回應 HTTP \(c)"
        case .checksumMismatch: return "下載的檔案 sha256 跟 Release 寫的不一樣，已丟棄"
        case .noAppInZip: return "zip 裡沒有 HearMe.app"
        case .signature(let why): return "新版本的簽章跟目前這個 app 不同，已丟棄（\(why)）"
        case .notAnAppBundle: return "目前不是從 .app 啟動，無法自動更新"
        case .translocated: return "app 在隔離路徑執行，請先把 HearMe.app 移到「應用程式」再試"
        case .notWritable(let p): return "無法寫入 \(p)"
        case .tool(let t, let out): return "\(t) 失敗：\(out)"
        }
    }
}

enum Updater {
    static let repo = "river0825/hear-me"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    /// The bundle we are running from, if it is a .app (nil for `swift run` / .build binaries).
    static var installedAppURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    // MARK: check

    static func fetchLatest() async throws -> ReleaseInfo {
        var req = URLRequest(url: latestURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("HearMe/\(currentVersion?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        return try ReleaseInfo.parse(data)
    }

    /// nil = already up to date (or version unknown).
    static func check(current: AppVersion? = currentVersion) async throws -> ReleaseInfo? {
        let latest = try await fetchLatest()
        guard let current else { Log.info("update: latest \(latest.tag), current version unknown (dev build)"); return nil }
        Log.info("update: latest \(latest.tag), current \(current)")
        return current < latest.version ? latest : nil
    }

    // MARK: install

    /// Download, verify and swap. `target` is the .app to replace (defaults to the running bundle).
    /// Returns the path of the new bundle (same as `target`).
    @discardableResult
    static func install(_ release: ReleaseInfo, over target: URL? = installedAppURL, status: @escaping (String) -> Void = { _ in }) async throws -> URL {
        guard let target else { throw UpdateError.notAnAppBundle }
        if target.path.contains("/AppTranslocation/") { throw UpdateError.translocated }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("hearme-update-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        status("下載 \(release.tag)…")
        let zip = try await download(release.zipURL, to: work.appendingPathComponent("HearMe.zip"))
        if let shaURL = release.shaURL {
            let shaFile = try await download(shaURL, to: work.appendingPathComponent("HearMe.zip.sha256"))
            let expected = try parseSha256(String(decoding: Data(contentsOf: shaFile), as: UTF8.self))
            let actual = sha256Hex(try Data(contentsOf: zip))
            guard expected == actual else { Log.warn("update: sha256 mismatch expected \(expected) got \(actual)"); throw UpdateError.checksumMismatch }
            Log.info("update: sha256 ok \(actual)")
        } else {
            Log.warn("update: release has no .sha256 asset, relying on signature check only")
        }

        status("驗證簽章…")
        let unpacked = work.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        guard let newApp = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noAppInZip }
        try? run("/usr/bin/xattr", ["-rd", "com.apple.quarantine", newApp.path])
        try verifySignature(of: newApp, matching: target)

        status("安裝…")
        try swap(newApp: newApp, into: target)
        Log.info("update: installed \(release.tag) at \(target.path)")
        return target
    }

    static func download(_ url: URL, to dest: URL) async throws -> URL {
        var req = URLRequest(url: url, timeoutInterval: 180)
        req.setValue("HearMe/\(currentVersion?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// `shasum -a 256` output: "<hex>  <name>".
    static func parseSha256(_ text: String) throws -> String {
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
        guard token.count == 64, token.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.badResponse }
        return token.lowercased()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Apple Developer team that signs official builds ("Developer ID Application", hq/ios/setup-developer-id.sh).
    static let teamId = "437258HXBJ"
    /// Standard Developer ID designated requirement, pinned to our team and bundle identifier. Lets an app
    /// signed with the older self-signed "HearMe Dev" identity move to Developer ID builds once, and keeps
    /// working across certificate renewals (a renewed cert has the same team OU).
    static let developerIdRequirement = "identifier \"xyz.riverdm.hearme\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"\(teamId)\""

    /// The new bundle must satisfy either the installed bundle's designated requirement
    /// (`identifier "xyz.riverdm.hearme" and certificate leaf = H"…"` for "HearMe Dev" builds) or the
    /// Developer ID requirement above. Ad-hoc builds carry a cdhash requirement that no other build
    /// satisfies, so they cannot self-update to anything but a Developer ID build.
    static func verifySignature(of newApp: URL, matching installed: URL) throws {
        var installedCode: SecStaticCode?
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(installed as CFURL, [], &installedCode) == errSecSuccess, let installedCode else {
            throw UpdateError.signature("讀不到目前 app 的簽章")
        }
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError.signature("讀不到新版本的簽章")
        }
        var candidates: [(label: String, requirement: SecRequirement)] = []
        var installedReq: SecRequirement?
        if SecCodeCopyDesignatedRequirement(installedCode, [], &installedReq) == errSecSuccess, let installedReq {
            var str: CFString?
            SecRequirementCopyString(installedReq, [], &str)
            candidates.append((str as String? ?? "installed DR", installedReq))
        }
        var devIdReq: SecRequirement?
        if SecRequirementCreateWithString(developerIdRequirement as CFString, [], &devIdReq) == errSecSuccess, let devIdReq {
            candidates.append(("Developer ID team \(teamId)", devIdReq))
        }
        guard !candidates.isEmpty else { throw UpdateError.signature("目前 app 沒有指定需求") }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var failures: [String] = []
        for (label, requirement) in candidates {
            var cfError: Unmanaged<CFError>?
            let status = SecStaticCodeCheckValidityWithErrors(newCode, flags, requirement, &cfError)
            if status == errSecSuccess {
                Log.info("update: new bundle satisfies [\(label)]")
                return
            }
            let why = (cfError?.takeRetainedValue()).map { "\($0)" } ?? "OSStatus \(status)"
            failures.append("[\(label)]: \(why)")
        }
        Log.warn("update: signature check failed " + failures.joined(separator: "; "))
        throw UpdateError.signature(failures.last ?? "?")
    }

    /// Move the old bundle aside, put the new one at its path, then trash the old one.
    static func swap(newApp: URL, into target: URL) throws {
        let fm = FileManager.default
        let aside = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).old-\(Int(Date().timeIntervalSince1970))")
        try fm.moveItem(at: target, to: aside)
        do {
            try fm.moveItem(at: newApp, to: target)
        } catch {
            try? fm.moveItem(at: aside, to: target)
            throw error
        }
        do { try fm.trashItem(at: aside, resultingItemURL: nil) } catch { try? fm.removeItem(at: aside) }
    }

    /// Launch `url` once this process has exited (so the new bundle does not collide with the running one).
    static func relaunchAfterExit(_ url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", url.path]
        do { try p.run(); Log.info("update: relaunch helper started for \(url.path)") } catch { Log.warn("update: relaunch helper failed: \(error)") }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw UpdateError.tool(tool, out.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
