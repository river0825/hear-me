# Hear Me（hearme）

POC：macOS 選單列語音輸入，對標 Typeless（按住快捷鍵說話、放開就把整理好的文字貼進目前的 app）。
狀態與證據：`docs/STATUS.md`。公司層規範在 `../CLAUDE.md`。

## 規則
- **全程裝置端，不連外**：辨識用 Apple `SpeechAnalyzer`／`SpeechTranscriber`（macOS 26+），整理用 Apple `FoundationModels` 裝置端模型。不要加任何雲端 API、不要加 runtime 依賴；需要時列進 STATUS 待裁決。唯一例外（CEO 2026-10-23 核准）：`Core/Updater.swift` 向 GitHub Releases API 查最新版、下載 `HearMe.zip`，不帶任何使用者資料，設定可關。
- 自動更新的安全線不能放寬：下載檔要過 Release 附的 sha256，且新 bundle 必須滿足**正在跑的 app 的指定需求**（同 identifier＋同憑證）**或** `Updater.developerIdRequirement`（identifier＋Apple 錨點＋team OU 437258HXBJ）。ad-hoc 簽的 build 只能更新到 Developer ID build。v0.1.7 以前的 app 只認「HearMe Dev」，換成 Developer ID 後那些版本要手動裝一次。
- 授權 MIT（`LICENSE`，CEO 2026-10-23 選定）。
- 純 SwiftPM（`Package.swift`），沒有 Xcode 專案。`swift build`、`swift test`、`scripts/bundle.sh` 產 `build/HearMe.app`。簽章順序：`~/Library/Keychains/apple-signing.keychain-db` 裡的「Developer ID Application」（Apple Developer team 437258HXBJ，hardened runtime＋`Resources/HearMe.entitlements` 的麥克風 entitlement，由 `../hq/ios/setup-developer-id.sh` 建）→ `hearme-dev.keychain-db` 的自簽「HearMe Dev」→ ad-hoc。發版用 `scripts/release-local.sh <版本>`（Developer ID 簽、公證、建 GitHub Release；不要只推 tag 讓 CI 出自簽版）。Developer ID 簽完用 `scripts/notarize.sh` 公證＋staple（App Store Connect API 金鑰在 gopass `services/apple/asc-api-key/`）。`scripts/send.sh` 用固定 croc 碼傳給 CEO。
- 這台開發機沒有麥克風，也沒給終端機輔助使用權限：聽寫 pipeline 用 `scripts/make-test-audio.sh` 產的音檔走 `HearMe --transcribe` 測；真實收音、快捷鍵、貼上要 CEO 在有麥克風的機器上驗，沒驗過的不能寫成已完成。
- 改提示詞（`Core/Polisher.swift`）後重跑 `docs/evidence/` 的五個案例並更新 `run-*.txt`；改口、條列、字典、英文不翻譯、翻譯這五件事都要仍然對。
- 使用者資料只在本機：記錄檔 `~/Library/Application Support/HearMe/history.jsonl`、更正記憶 `corrections.json`，不上傳、不收集。更正記憶的安全規則（中文 1 字、英文 2 字母以內不記）在 `Core/Corrections.swift`，不要放寬。
- 遠端 repo 在 GitHub：https://github.com/river0825/hear-me（公開）。push 到 main 不會觸發部署，屬自主動作。
- CI/CD 在 GitHub Actions（`.github/workflows/`）：push main／PR 在 `macos-26` runner 跑 `swift build`、`swift test`；push `v*` tag 自動用 CI 裡的「HearMe Dev」身分打包、簽章並建 GitHub Release 附 `HearMe.zip`。runner、Xcode 版本、secret 名稱與發版步驟見 `docs/STATUS.md`「CI/CD」。
- 與 CEO 溝通用台灣正體中文；程式識別字與註解用英文。
