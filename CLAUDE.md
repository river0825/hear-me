# 說寫（shuoxie）

POC：macOS 選單列語音輸入，對標 Typeless（按住快捷鍵說話、放開就把整理好的文字貼進目前的 app）。
狀態與證據：`docs/STATUS.md`。公司層規範在 `../CLAUDE.md`。

## 規則
- **全程裝置端，不連外**：辨識用 Apple `SpeechAnalyzer`／`SpeechTranscriber`（macOS 26+），整理用 Apple `FoundationModels` 裝置端模型。不要加任何雲端 API、不要加 runtime 依賴；需要時列進 STATUS 待裁決。
- 純 SwiftPM（`Package.swift`），沒有 Xcode 專案。`swift build`、`swift test`、`scripts/bundle.sh` 產 `build/ShuoXie.app`（ad-hoc 簽名；每次重打包後「輔助使用」權限要重新勾）。
- 這台開發機沒有麥克風，也沒給終端機輔助使用權限：聽寫 pipeline 用 `scripts/make-test-audio.sh` 產的音檔走 `ShuoXie --transcribe` 測；真實收音、快捷鍵、貼上要 CEO 在有麥克風的機器上驗，沒驗過的不能寫成已完成。
- 改提示詞（`Core/Polisher.swift`）後重跑 `docs/evidence/` 的五個案例並更新 `run-*.txt`；改口、條列、字典、英文不翻譯、翻譯這五件事都要仍然對。
- 使用者資料只在本機：記錄檔在 `~/Library/Application Support/ShuoXie/history.jsonl`，不上傳、不收集。
- 與 CEO 溝通用台灣正體中文；程式識別字與註解用英文。
