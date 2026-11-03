# Hear Me（hearme；原名〈說寫〉）
- 一句話：macOS 選單列語音輸入工具：按住 fn（或右 ⌥、右 ⌘）說話、放開，整理好的文字就貼進你正在用的 app；辨識與整理全在這台電腦上完成。（來源：hearme/README.md 這是什麼）
- 平台與網址：macOS 26 以上、Apple Silicon；下載 https://github.com/river0825/hear-me/releases （`HearMe.zip`）。只有 macOS；Windows、iOS 沒有計畫。（來源：hearme/README.md 需求、安裝、已知限制）
- 狀態：公開（GitHub 公開 repo，MIT 授權）；v0.2.0 起為 Apple Developer ID 簽章並公證的版本。（來源：hearme/docs/STATUS.md 首段、10-29 第十一輪；README.md 授權）
- 價格：文件寫「沒有帳號、沒有訂閱」、開源 MIT；未寫售價。（來源：README.md 這是什麼、授權）
- 聯絡方式：**文件未寫**（README 沒有列 GitHub Issues、信箱或任何回報管道；只有 Releases 下載頁）。（來源：hearme/README.md、docs/STATUS.md 全文查無）

## 常見問題（只寫文件明確支持的事實）
- Q: 會把我的聲音傳到雲端嗎？ A: 不會。辨識用 Apple `SpeechAnalyzer`，整理用 Apple 裝置端 Foundation Model，不連網、沒有雲端 API、沒有帳號。唯一的對外連線是向 github.com 查最新版本號與下載更新檔，不帶使用者資料，可在設定關掉。記錄檔只在本機（`~/Library/Application Support/HearMe/history.jsonl`、`corrections.json`），隨時可刪。（來源：README.md 這是什麼、隱私）
- Q: 需要什麼？ A: macOS 26 以上、Apple Silicon（Intel Mac 文件未寫，STATUS 對照表只寫「只有 macOS 26+（Apple Silicon、Apple Intelligence 開啟）」）；整理功能需要「系統設定 → Apple Intelligence 與 Siri」打開（會下載幾 GB 模型），沒開就退回規則清理仍可用；權限：輔助使用、麥克風。（來源：README.md 需求）
- Q: 怎麼安裝？ A: 下載 `HearMe.zip`，解壓後把 `HearMe.app` 放進「應用程式」；沒有 Dock 圖示與主視窗，只在選單列出現麥克風圖示；系統會要「輔助使用」，第一次聽寫時要麥克風。用 fn 鍵要把「系統設定 → 鍵盤 → 按下 🌐 鍵時」改成「不做任何動作」，或改用右 ⌥。（來源：README.md 安裝）
- Q: 系統說無法打開（未驗證的開發者）／打不開？ A: v0.2.0 起（目前最新版）都用 Apple Developer ID 簽並經 Apple 公證，正常不會出現這個警告（2026-11-03 從 GitHub 下載最新版實測：`source=Notarized Developer ID`）。出現的話多半是裝到 v0.1.7 以前的自簽版。請使用者：(1) 在 Finder 對 HearMe.app 按右鍵 →「取得資訊」看版本，或終端機跑 `spctl -a -vv /Applications/HearMe.app`（公證版顯示 `source=Notarized Developer ID`，自簽版顯示 `origin=HearMe Dev`）；(2) 刪掉舊版，到 https://github.com/river0825/hear-me/releases/latest 重新下載 `HearMe.zip`（不是 Source code），解壓放進「應用程式」再開，並重新允許輔助使用與麥克風；(3) 一定要用舊版才需要 `xattr -cr /Applications/HearMe.app`；(4) 最新版仍出現警告，請回信附上版本與 `spctl -a -vv` 的輸出，轉給工程確認。（來源：README.md 安裝 4、已知限制；docs/evidence/run-gatekeeper-2026-11-03.txt）
- Q: 怎麼更新？ A: app 啟動時與每 6 小時向 GitHub 查最新版本（可關），有新版會在選單最上面出現「有新版本 vX.Y.Z，下載並安裝…」，會核對 sha256 與簽章後換掉並重啟；也可選單「檢查更新…」。app 要放在使用者寫得到的資料夾。（來源：README.md 安裝 5；docs/STATUS.md 第九輪）
- Q: 支援哪些語言？ A: 為台灣華語夾英文技術詞設計，也能用英文、日文；主語言＋第二語言兩個模型同時聽（預設 zh_TW＋en_US），不是自動偵測一百種。輸出語言可選英文、日文、台灣正體中文。（來源：README.md 功能、已知限制）
- Q: 功能有哪些？ A: 按住說放開貼／快速點一下持續聽；去填充詞、去重複、改口只留最後；補標點、明確列舉才條列；每個 app 不同語氣（可自訂 bundle id）；個人字典；更正記憶（「更正上一次聽寫…」或「從選取文字學習」）；晶晶體中英修拼字與加空格；翻譯；按住 ⇧＋快捷鍵對選取文字下語音指令。（來源：README.md 功能、使用）
- Q: 出問題怎麼辦？ A: 選單列 →「檢查權限…」與「顯示 log 檔」（`~/Library/Logs/HearMe.log`）；選單另有「取消（強制回到待命）」。（來源：README.md 使用；docs/STATUS.md 第二輪）

## 已知限制與未開放功能
- 整理模型是 Apple 裝置端小模型：改口「不對」處理得好，「不是」這類語意含糊的會保留原句；翻譯會把專有名詞直譯。（來源：README.md 已知限制）
- 沒做：個人化風格學習、Windows／手機版、HUD 波形、「Ask anything」查資料（會連外）。（來源：docs/STATUS.md 對照表、已知限制）
- 辨識的時間可能寫成「3:00」「1st」，整理通常改回但不保證。（來源：docs/STATUS.md 已知限制）
- fn 鍵的系統預設動作要使用者自己改。（來源：docs/STATUS.md 已知限制）

## 不要承諾的事
- Windows／iOS 版、特定辨識準確率、新語言或功能的時程；授權以 MIT 為準，其他法律問題轉人工。
