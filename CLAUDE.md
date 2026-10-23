# Hear Me（hearme）

POC：macOS 選單列語音輸入，對標 Typeless（按住快捷鍵說話、放開就把整理好的文字貼進目前的 app）。
狀態與證據：`docs/STATUS.md`。公司層規範在 `../CLAUDE.md`。

## 規則
- **全程裝置端，不連外**：辨識用 Apple `SpeechAnalyzer`／`SpeechTranscriber`（macOS 26+），整理用 Apple `FoundationModels` 裝置端模型。不要加任何雲端 API、不要加 runtime 依賴；需要時列進 STATUS 待裁決。
- 純 SwiftPM（`Package.swift`），沒有 Xcode 專案。`swift build`、`swift test`、`scripts/bundle.sh` 產 `build/HearMe.app`，用 `~/Library/Keychains/hearme-dev.keychain-db` 裡的自簽身分「HearMe Dev」簽（讓權限不用每次重勾）；那個 keychain 不在時退回 ad-hoc。`scripts/send.sh` 用固定 croc 碼傳給 CEO。
- 這台開發機沒有麥克風，也沒給終端機輔助使用權限：聽寫 pipeline 用 `scripts/make-test-audio.sh` 產的音檔走 `HearMe --transcribe` 測；真實收音、快捷鍵、貼上要 CEO 在有麥克風的機器上驗，沒驗過的不能寫成已完成。
- 改提示詞（`Core/Polisher.swift`）後重跑 `docs/evidence/` 的五個案例並更新 `run-*.txt`；改口、條列、字典、英文不翻譯、翻譯這五件事都要仍然對。
- 使用者資料只在本機：記錄檔 `~/Library/Application Support/HearMe/history.jsonl`、更正記憶 `corrections.json`，不上傳、不收集。更正記憶的安全規則（中文 1 字、英文 2 字母以內不記）在 `Core/Corrections.swift`，不要放寬。
- 遠端 repo 在 GitHub：https://github.com/river0825/hear-me（私人）。push 到 main 不會觸發部署，屬自主動作。
- CI/CD 在 GitHub Actions（`.github/workflows/`）：push main／PR 在 `macos-26` runner 跑 `swift build`、`swift test`；push `v*` tag 自動用 CI 裡的「HearMe Dev」身分打包、簽章並建 GitHub Release 附 `HearMe.zip`。runner、Xcode 版本、secret 名稱與發版步驟見 `docs/STATUS.md`「CI/CD」。
- 與 CEO 溝通用台灣正體中文；程式識別字與註解用英文。
