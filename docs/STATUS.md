# Hear Me STATUS

原名〈說寫〉（shuoxie），CEO 10-23 15:5x 指示改名 Hear Me 並放上 GitHub：https://github.com/river0825/hear-me（CEO 10-23 17:4x 指示改公開）。

最後更新：2026-10-23 17:50（第六輪：模型回答問句的防呆）

## 是什麼
CEO 10-23 直接交辦：「參考 Typeless 的功能，寫一個可以語音輸入的軟體」。
做出來的是 macOS 選單列 app〈Hear Me〉：按住 fn（或右 ⌥／右 ⌘）說話，放開後把 Apple 裝置端語音辨識的逐字稿交給 Apple 裝置端模型整理（去填充詞、去重複、改口只留最後、補標點、明確列舉才條列、依 app 換語氣、個人字典、翻譯），再用 ⌘V 貼進原本在用的 app，剪貼簿還原。**全程不連外，沒有任何雲端 API 或 runtime 依賴。**

## Typeless 功能對照（來源：typeless.com 首頁與定價頁，10-23 抓）

| Typeless | Hear Me 這一輪 | 備註 |
|---|---|---|
| 按住說話、貼進任何 app | ✅ fn／右⌥／右⌘ 按住說、放開貼；快速點一下＝持續聽到下一次點 | 快捷鍵與貼上需要「輔助使用」權限 |
| 去填充詞、去重複 | ✅ 裝置端模型；「照打」模式只用規則 | 證據 `docs/evidence/run-*.txt` |
| 改口只留最後（「三點，不對，四點」） | ✅ 逐字稿有「不對／不是／應該是」時加提醒 | 「不對」穩定；「不是」這種語意含糊的會保留原句（見 run-zh-correction.txt 第三例） |
| 自動排版（清單、步驟） | ✅ 只在明確列舉三項以上才條列 | 第一版什麼都條列，已修 |
| 個人字典 | ✅ 同時餵給辨識（contextual strings）與整理模型 | 辨識端對 TTS 的「IronNote」沒救回，整理端 3/3 修回 |
| 更正記憶（Typeless 的「字典自動加入」） | ✅ 10-23 第三輪：「錯的→對的」配對存本機；逐字稿一出來先確定性替換，再告訴整理模型，右邊的詞也餵給辨識器。兩個入口：選單「更正上一次聽寫…」（圈選原文裡錯的、打正確的）、「從選取文字學習」（在原 app 改對後選起來，程式跟上一次輸出做差異比對） | CEO 10-23 16:0x 提議；證據 `run-corrections.txt` |
| 每個 app 不同語氣 | ✅ bundle id → 一般／正式／口語／照打；預設郵件正式、通訊軟體口語、終端機與編輯器照打 | 設定頁可改，支援前綴規則 |
| 100+ 語言、自動偵測 | ✅ 兩種語言自動偵測（10-23 第四輪）：主語言＋第二語言兩個模型同時聽同一段聲音，放開後用「信心 × 文字系統比對」挑一個；整理模型也跟著用該語言的規則。預設 zh_TW＋en_US | 不是 100 種；只有兩種。10-23 17:4x CEO 說「直接把它變成公開的 repo」被英文模型搶走（「So the champions and Gong Kai」），規則收緊：只有主語言模型自己吐出非本語言文字（漢字比例＜0.5）才考慮第二語言。證據 `run-dual-language.txt` |
| 翻譯 | ✅ 輸出語言：英文／日文／台灣正體中文 | 日文把「首頁」直譯了；en→zh 用了「崩潰」「發送」等非台灣用語 |
| 選取文字下語音指令（改短、換語氣、翻譯、摘要、提問） | ✅ 按住 ⇧＋快捷鍵；先 ⌘C 抓選取文字，說完指令後貼回 | 檔案路徑驗過「翻成英文、正式一點」與「縮短成一句」 |
| 個人化風格學習 | ❌ 沒做 | 需要累積記錄再做 |
| 隱私：零雲端、不訓練、記錄在本機 | ✅ 比 Typeless 更嚴：根本不連網 | 記錄 `~/Library/Application Support/HearMe/history.jsonl` |
| Windows／iOS／Android | ❌ 只有 macOS 26+（Apple Silicon、Apple Intelligence 開啟） | |
| 「Ask anything」查資料、開網頁 | ❌ 不做（會連外） | |

## 怎麼跑

```
builtin cd hearme
swift build                      # 需要 Xcode 26+（macOS 27 SDK），Swift 5 語言模式
swift test                       # 14 個單元測試（按住／點一下狀態機、規則清理、語氣對照、記錄檔、提示詞）
./scripts/bundle.sh              # 產 build/HearMe.app（release，ad-hoc 簽名）；傳給別台：ditto -c -k --keepParent build/HearMe.app build/HearMe.zip 再 croc send
open build/HearMe.app           # 選單列出現麥克風圖示；第一次會要「輔助使用」與「麥克風」

# 無麥克風的機器：走檔案路徑
./scripts/make-test-audio.sh     # 用系統 TTS 產 4 段測試音檔到 docs/evidence/（gitignore）
.build/debug/HearMe --doctor
.build/debug/HearMe --simulate-live docs/evidence/zh-list.wav --polish --verbose   # 即時路徑（麥克風串流）用音檔模擬
.build/debug/HearMe --transcribe docs/evidence/zh-list.wav --polish --tone casual --dict "release notes"
.build/debug/HearMe --polish-text "嗯 我明天 呃 明天下午三點 不對 四點 要跟客戶開會"
.build/debug/HearMe --command "<選取的文字>" --say "幫我翻成英文"
HEARME_DEMO=1 build/HearMe.app/Contents/MacOS/HearMe   # 啟動 1 秒後自動開始聽寫
.build/debug/HearMe --render-ui docs/evidence/ui          # HUD 各狀態與設定頁離屏畫成 PNG
```

第一次用 fn 鍵前，到「系統設定 → 鍵盤 → 按下 🌐 鍵時」改成「不做任何動作」，否則系統自己的聽寫／表情符號會跟著跳出來。

## 證據（10-23，這台 Mac Studio，M3 Ultra、macOS 27.0）

| 關卡 | 結果 | 證據 |
|---|---|---|
| 編譯、單元測試 | `swift build` 過；`swift test` 14/14 | 本檔；重跑即可 |
| 裝置端模型可用 | `SystemLanguageModel.default.availability == available` | `--doctor` 輸出 |
| 語音辨識（檔案） | zh_TW 6.4 秒音檔 0.2–0.5 秒出稿；en_US 第一次 12.8 秒（含下載模型），之後 0.2 秒 | `docs/evidence/run-*.txt` |
| 整理（裝置端模型） | 每段 0.6–1.5 秒 | 同上 |
| 改口 | 「三點 不對 四點」→「我明天下午四點要跟客戶開會，你幫我記一下。」 | `run-zh-correction.txt` |
| 條列 | 「三件事 第一…第二…第三…」→ 編號三行；一般句子不條列 | `run-zh-list.txt`、`run-zh-correction.txt` |
| 字典 | 辨識出「Irannote」，整理後 3/3 次是「IronNote」；「繪出」→「匯出」 | `run-zh-dict.txt` |
| 英文不被翻譯、去 um/uh/you know | ✅ | `run-en-filler.txt` |
| 翻譯 | 中→英、中→日、英→中 | `run-translate.txt` |
| 選取文字下指令 | 翻成英文並正式化、縮短 | `run-command-and-translate.txt` |
| app 啟動 | `build/HearMe.app` 以 `HEARME_DEMO=1` 啟動，跑 5 秒沒 crash，log 只有「Accessibility not granted yet」 | `docs/evidence/app-launch.log` |
| HUD 與設定頁外觀 | `screencapture` 被擋（終端機沒有螢幕錄製權限），改用 `--render-ui` 離屏畫出 5 個 HUD 狀態與設定頁 | `docs/evidence/ui/*.png` |
| 即時路徑（麥克風串流的那條程式路徑） | `--simulate-live` 把音檔切成麥克風大小的塊餵進即時辨識：三段都 44 筆左右的即時更新、最後一筆 final、收尾 0.06 秒 | `run-simulate-live.txt` |
| **真人收音、快捷鍵／選單啟動、貼進別的 app** | ✅ **CEO 的 Mac 10-23 16:04–16:06 通過**：內建麥克風 48 kHz → 16 kHz，五段真實語音即時辨識、收尾 0.03–0.17 秒、貼上。第一次因麥克風權限 2.5 秒才起來、0 buffer，之後都正常 | `docs/evidence/ceo-mac-log-2026-10-23.txt`（CEO 貼來的 log） |

## 10-23 第二輪：CEO 那台卡在「聽寫中」關不掉
CEO 的 Mac（macOS 26.6.2、Apple Silicon、Apple Intelligence 未開）用選單「開始聽寫」後一直聽寫中、關不掉。在這台機器用 `--simulate-live` 重現並修了三件事：
1. 辨識結果迴圈每筆都 `await MainActor.run` 回報 UI，主執行緒一忙就整條卡住（CLI 模式 8.7 秒音訊只收到一個字）。改成 `DispatchQueue.main.async`。
2. 分析器收尾後結果流不一定會結束，`await resultsTask.value` 永遠等不到。改成最多等 1.5 秒，之後用已累積的文字。
3. 我寫的逾時包裝用 task group，group 會等子任務結束才返回，逾時形同沒有。改成 continuation 競速。
另外加了：啟動 20 秒逾時、收尾 8 秒逾時、選單「取消（強制回到待命）」、log 寫到 `~/Library/Logs/HearMe.log`（選單「顯示 log 檔」）。
**CEO 那台的根因還沒確認**（沒有 log），新版若再卡住，請把 log 檔貼過來。

## 10-23 第四輪：從 CEO 的 log 修的三件事
1. **Apple Intelligence 沒開**（`appleIntelligenceNotEnabled`；CEO 10-23 晚上回報已在系統設定開好）：整理模型跟 Apple Intelligence 共用裝置端模型，系統沒開就不可用。沒開時輸出＝規則清理；規則清理加了「去掉中文標點前後的空格」（辨識器會寫成「功能 ，看」）。
2. **中文模式說整句英文變亂碼**：做了兩種語言自動偵測（見對照表）。
3. **每次重打包要重勾輔助使用**：ad-hoc 簽名的指定需求含 cdhash，每次都變。改用自簽的「HearMe Dev」程式碼簽章身分（openssl 產、放在獨立的 `~/Library/Keychains/hearme-dev.keychain-db`，無密碼；公鑰憑證在 `Resources/HearMeDev.cer.pem`），指定需求變成「identifier + 憑證指紋」，重打包不變。`scripts/bundle.sh` 偵測到那個 keychain 就用它簽，沒有就退回 ad-hoc。**還沒在 CEO 那台驗證 TCC 真的接受未信任的自簽憑證**；下一次重打包後 log 若 `ax=true`，就是過了。這把身分只保護「權限不用重勾」，遺失就重做一把、重勾一次權限。

## 要 CEO 驗（有麥克風的 Mac，macOS 26+，Apple Intelligence 開啟）
1. `./scripts/bundle.sh && open build/HearMe.app`，允許「輔助使用」（系統會跳出）與「麥克風」（第一次聽寫時跳出）。
2. 開備忘錄，按住 fn 說「嗯 明天下午三點 不對 四點 跟客戶開會 幫我記一下」，放開。預期 2 秒內貼上「明天下午四點跟客戶開會，幫我記一下。」
3. 開郵件寫信，同一句，預期語氣變正式（「您」）。開終端機，預期只去填充詞、不改寫。
4. 選一段文字，按住 ⇧+fn 說「幫我翻成英文」，預期選取處被英文取代。
5. 快速點一下 fn，講一段長的，再點一下結束。
6. 看 `~/Library/Application Support/HearMe/history.jsonl` 有沒有每一筆的 raw／output／秒數。

## 10-23 第三輪：更正記憶（CEO 提議「圈選錯的、輸入正確的，以後記住」）
辨識準確率三層：(1) 辨識前偏好＝個人字典→contextual strings（已有，只能偏向）；(2) 辨識後確定性更正＝這輪做的；(3) Apple 自訂語言模型（`SFCustomLanguageModelData`）只接在舊式 `DictationTranscriber`，新的 `SpeechTranscriber` 沒有這個口，沒做。
做法改成「貼上之後」更正而不是聽寫中：HUD 收音中不接滑鼠。安全規則：中文 1 個字、英文 2 個字母以內的片段不記（全域替換會誤傷）；差異比對時英數字擴到整個單字、中文往左補到 3 個字。

## CI/CD（GitHub Actions，10-23 第五輪）

| 工作流程 | 觸發 | runner／工具 | 做什麼 |
|---|---|---|---|
| `.github/workflows/ci.yml` | push `main`、pull_request | `macos-26`（GitHub 託管 arm64 映像 `macos-26-arm64`，macOS 26.6.2）；`sudo xcode-select -s /Applications/Xcode_26.6.app`（Xcode 26.6 / Swift 6.3.3 / macOS 26.5 SDK） | `swift build`、`swift test` |
| `.github/workflows/release.yml` | push `v*` tag；手動 workflow_dispatch（只出 artifact、不建 release） | 同上 | 匯入自簽身分 → `scripts/bundle.sh` → `codesign -dv --verbose=2`／`-d -r-`／`--verify --strict` 印進 log → `ditto -c -k --keepParent` 成 `build/HearMe.zip` + sha256 → 上傳 artifact `HearMe-<tag>` → `gh release create <tag>` 附 zip 與 sha256，notes＝上個 tag 以來的 commit 清單 + GitHub 自動產生的 |

- **簽章身分**：release 從 repo secret `HEARME_SIGN_P12_BASE64`（「HearMe Dev」p12 的 base64）與 `HEARME_SIGN_P12_PASSWORD` 匯進 runner 的 `~/Library/Keychains/hearme-dev.keychain-db`（與 `bundle.sh` 找的路徑相同），再用 `Resources/HearMeDev.cer.pem` 加進系統信任；secret 不在時印 warning、退回 ad-hoc。p12 與私鑰不進 repo；遺失就重做一把、重設 secret、重勾一次權限。
- **版本號**：`bundle.sh` 讀 `HEARME_VERSION`（tag 去掉 v）與 `HEARME_BUILD`（run number）寫進 Info.plist；本機跑不帶這兩個變數就維持 `Resources/Info.plist` 的值。
- **怎麼發版**：`git tag v0.1.2 && git push origin v0.1.2`。約 1–2 分鐘後 zip 在 `https://github.com/river0825/hear-me/releases/tag/v0.1.2`，同一份也在該 run 的 Artifacts。tag 已有 release 時改為覆蓋上傳資產。
- **證據（v0.1.0，10-23 17:1x）**：
  - CI run #1 綠：https://github.com/river0825/hear-me/actions/runs/39930719474 — build 11 秒、23/23 XCTest 過、整個 job 31 秒。
  - Release run #1 綠：https://github.com/river0825/hear-me/actions/runs/39930875737 — log 印出 `1 valid identities found`、`Authority=HearMe Dev`、`designated => identifier "xyz.riverdm.hearme" and certificate leaf = H"9b1df6796456df0b21c86d051fea503f6454b077"`、`satisfies its Designated Requirement`、Info.plist 0.1.0。
  - Release：https://github.com/river0825/hear-me/releases/tag/v0.1.0 — `HearMe.zip` 1,426,761 bytes，sha256 `f234bb6b…0fb771e2`。
  - 下載回這台 Mac 解開比對：sha256 與 log 一致；`codesign -d -r-` 的指定需求與本機 `bundle.sh` 產的**完全相同**，`codesign --verify --strict` 過。對 TCC 來說 CI 打包＝本機打包，權限不用重勾（前提仍是 S-1：TCC 接受自簽憑證還沒在 CEO 那台驗）。
- **證據（v0.1.1，10-23 17:2x）**：改完 release notes 由 commit 產生後第一次 tag 失敗——runner 的 `/bin/bash` 是 3.2，`$TAG）`（全形括號）會把多位元組字元的第一個 byte 吃進變數名，`TAG\xef: unbound variable`；改成 `${TAG}）` 後重打 tag。Release run 綠：https://github.com/river0825/hear-me/actions/runs/39931510614；release https://github.com/river0825/hear-me/releases/tag/v0.1.1（notes 列出 v0.1.0 → v0.1.1 的兩個 commit；`HearMe.zip` 1,426,773 bytes，Info.plist 0.1.1 / build 4，指定需求同上）。手動 workflow_dispatch 也驗過：https://github.com/river0825/hear-me/actions/runs/39931356901 只出 artifact `HearMe-main`、不建 release。
- **寫 workflow 的坑**：runner 的 bash 是 3.2，變數後面接中文或全形標點一律用 `${VAR}`；`bundle.sh` 最後那行 `grep` 在自簽身分下沒有 `Authority=`（未受信任的憑證不印）會讓 `pipefail` 的腳本以 1 結束，已加 `|| true`。
- **為什麼選 `macos-26`**：這個 app 要 macOS 26 SDK 才編得過、測試包要 macOS 26+ 才載得起來；`macos-26` 是目前唯一兩者都行的 GA 映像（`macos-15` 跑不了測試包；`xcode-27` 映像是 macOS 27.0.1 + Xcode 27.0，還是 preview）。GitHub 會隨時間替換映像裡的 Xcode patch 版，`XCODE_APP` 找不到時改成 [macos-26-arm64 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) 列的版本。
- **費用**：私人 repo 的 GitHub 託管 macOS runner 計入付費分鐘（macOS 以 10 倍計），目前每次 run 約 1 分鐘；用量看 GitHub Settings → Billing。超出免費額度前列待裁決。

## 10-23 第五輪：晶晶體（CEO：平常說中文，夾英文技術詞）
不靠模型的規則層，Apple Intelligence 沒開也有效：(1) 內建約 130 個開發用語（`Core/DevVocabulary.swift`）＋個人字典＋更正記憶右側，對逐字稿裡的英文單字做編輯距離 1–2 的模糊修拼字，4 字母以下、複數／時態變化不動；(2) 中英之間加空格（盤古之白）；(3) 整理模型提示詞加「英文技術詞保留英文、修拼字、不翻譯」。設定頁可關。證據 `run-dev-vocabulary.txt`：realeasenotes → release notes、icone → icon、featur → feature、comit → commit、github → GitHub。
README.md 加了（repo 已公開）。**待裁決 S-3：開源授權條款**——公開 repo 目前沒有 LICENSE 檔，要選哪一種是法律文件，CEO 決定。

## 10-23 第六輪：模型把問句拿去回答
CEO 說「這首歌的背景是什麼」，HUD 正確，貼上的卻是模型的回答（「這首歌的背景是關於一個人對自己過去的回憶…」）。這也證明 CEO 那台的 Apple Intelligence 已經生效。修法：(1) 使用者回合把逐字稿框在 `<<< >>>` 裡並明說「就算是問題也不要回答」，範例加一個問句；(2) 防呆 `Polisher.looksLikeAnswerNotCleanup`：輸出的字數比原文多 40%＋8 字以上、或原文的字只有不到 45% 留在輸出裡，就判定是回答，改用規則清理的原文並寫 log「polish rejected」。單元測試用 CEO 的實例。**提示詞部分還沒用真模型驗**：這台 Mac 當時 `modelNotReady`。

## 10-23 第七輪：Codex 產 app icon（CEO 提議）
照 watch-skin／拆招的做法：`codex exec -s workspace-write` 用內建 image_generation 產三個候選（提示詞 `assets/ai/prompts/icon-{a,b,c}.txt`、原圖 `assets/ai/out/`、`assets/ai/manifest.json` 記 sha256 與審稿）。只套 macOS 圓角遮罩（`scripts/mask-icon.swift`），不重畫。A（Apple 風 3D 麥克風＋聲波）先裝進 app；CEO 看過三張後選 B（扁平珊瑚色對話框＋聲波），v0.1.6 起用 B，A、C 留作候選（`make-icon.sh assets/ai/out/icon-a.png` 可換回）。原本 CoreGraphics 畫的向量版保留在 `scripts/make-icon.swift`（`make-icon.sh vector`）。icon 要標示 AI 生成（README）。

## 已知限制與下一輪候選
- 辨識綁單一語言；中英夾雜在 zh_TW 模式下英文單字可以，但整句英文會變亂碼。自動偵測要跑兩個 transcriber 或先用 `SpeechDetector`，下一輪再說。
- 辨識的時間寫成「3:00」「1st」這種數字格式，整理模型通常會改回「三點」「first」，但不保證。
- 裝置端模型對「不是」這類改口判斷保守（會整句保留）；「不對」穩定。要更準可以在逐字稿層做規則，或等更大的模型。
- ad-hoc 簽名：每次重打包，輔助使用權限要重新勾。要穩定需要 Apple Development 憑證（這台機器 `security find-identity` 沒有任何簽章身分 → 待裁決：要不要用 CEO 的 Apple ID 建開發憑證）。
- fn 鍵的系統預設動作要使用者自己改；之後可以用 CGEvent tap 攔掉，但要「輸入監控」權限。
- 沒做：個人化風格學習、Windows／手機版、HUD 顯示波形、長句的即時逐字顯示只顯示最後 90 字。
- 日文翻譯會把中文專有名詞直譯（「首頁」）；可以在翻譯模式也餵字典對照。

## 10-23 第八輪：icon 定案 B、v0.1.6
CEO 看過三張候選選 B，`make-icon.sh` 預設改成 B，tag v0.1.6（Release 由 CI 出，croc 碼不變）。CEO 回報 Apple Intelligence 已設定好。

## 10-23 第九輪：MIT 授權、GitHub 自動更新（CEO 核准連 GitHub）
- `LICENSE` MIT（S-3 結案）。
- `Core/Updater.swift`：啟動 15 秒後與每 6 小時匿名打 `api.github.com/repos/river0825/hear-me/releases/latest`（設定「自動檢查更新」可關，預設開）。有新版 → 選單最上面「有新版本 vX，下載並安裝…」；按下後：下載 CI 出的 `HearMe.zip`＋`.sha256` → 比對 sha256 → `ditto` 解開、去隔離屬性 → 用 Security framework 檢查新 bundle **滿足正在跑的 app 的指定需求**（`identifier "xyz.riverdm.hearme" and certificate leaf = H"9b1d…b077"`）→ 舊 bundle 移到一旁再丟垃圾桶、新 bundle 放原路徑 → 用 `/bin/sh` 等舊程序退出後 `open` 新的。選單另有「檢查更新…」。CLI：`--check-update`、`--update --target <HearMe.app>`；GUI 無頭測試用 `HEARME_UPDATE_NOW=1`。
- 證據 `docs/evidence/run-update.txt`（這台 Mac 真跑）：(1) CLI 把本機打的 0.1.5 從 GitHub 更新到 v0.1.6，3.6 秒，`codesign --verify --strict` 過；(2) 反向：目標是 ad-hoc 簽的 → 簽章檢查失敗（-67050）、目標不動；(3) GUI：0.1.5 啟動 → 6 秒內下載、驗章、換掉、重啟，log 看到 `launched 0.1.6`，`lsof` 確認新程序跑的是 ~/Applications 裡換過的檔。
- 限制：app 要放在使用者寫得到的資料夾（應用程式或 ~/Applications 都可）；App Translocation（隔離路徑）下會拒絕並提示先移到應用程式；ad-hoc 簽的開發版不會自動更新（本機 `bundle.sh` 有 keychain 時都是 HearMe Dev 簽，沒問題）。
- **CEO 這次還是要用 croc 裝一次 v0.1.7**（第一個含更新器的版本），之後就從選單更新。沒驗的：CEO 那台的 TCC 在更新後是否仍 `ax=true`（簽章相同、路徑相同，理論上會）。

## 10-26 第十輪：Apple Developer 簽章（CEO 10-26 說「我現在有 apple developer 了，請幫忙 sign」）
公司 10-26 已有 Apple Developer team 437258HXBJ、App Store Connect API key（Admin）與 agent 用的 `apple-signing.keychain-db`（見 `../hq/ios/README.md`）。帳號上還沒有 Developer ID Application 憑證（API 查過 0 張），而 agent 建憑證會被 auto mode 分類器擋（Access Added As A Means，跟 hq/ios 當初一樣），所以做好了所有不用憑證的部分：
- `../hq/ios/setup-developer-id.sh`：用 ASC API 建 Developer ID Application 憑證、匯入 apple-signing keychain（含 Apple 的 Developer ID G2／WWDR G3 中繼憑證）、p12 備份到 gopass `services/apple/developer-id-cert/`。**要 CEO 跑一次**（`! hq/ios/setup-developer-id.sh`）。
- `scripts/bundle.sh`：有 Developer ID 就用它簽（`--options runtime --timestamp`＋`Resources/HearMe.entitlements` 的 `com.apple.security.device.audio-input`，hardened runtime 沒這條會收不到麥克風），沒有退回 HearMe Dev，再沒有退回 ad-hoc。已驗退回路徑：這台目前仍簽出 HearMe Dev 的指定需求。
- `scripts/notarize.sh`：zip → `notarytool submit --wait` → `stapler staple` → `spctl -a`。金鑰從 env 或 gopass `services/apple/asc-api-key/`。
- `Core/Updater.swift`：新 bundle 滿足「目前 app 的指定需求」**或**「Developer ID＋team OU 437258HXBJ＋identifier」其一即可，所以 HearMe Dev 簽的 app（跑這版以後的程式）可以自動換到 Developer ID 版；之後憑證到期換新也不會斷。測試 `testDeveloperIdRequirementParses`。
- `.github/workflows/release.yml`：有 `HEARME_DEVID_P12_BASE64`／`HEARME_DEVID_P12_PASSWORD` 就匯入 Developer ID 簽（並下載 Apple 中繼憑證）；有 `HEARME_ASC_KEY_P8_BASE64`／`HEARME_ASC_KEY_ID`／`HEARME_ASC_ISSUER_ID` 就公證＋staple；都沒有就照舊 HearMe Dev。
- 憑證建好後要做的：(1) 把 p12 與 ASC key 設成 GitHub secrets（`gh secret set` 從 gopass 讀）；(2) 本機 `bundle.sh`＋`notarize.sh` 真跑一次，`spctl -a -vv` 要看到 `source=Notarized Developer ID`；(3) tag 新版，CI 出公證過的 Release；(4) 用 HearMe Dev 簽的 app 跑更新器，驗它接受 Developer ID 版（證據補進 `run-update.txt`）。
- 影響 CEO：裝的 v0.1.7 只認 HearMe Dev，**換成 Developer ID 的第一版要手動裝一次**，輔助使用與麥克風權限因憑證不同會再問一次；之後就穩定了，而且不再需要 `xattr -cr`。
- **待裁決 S-5**：CI 公證要把 ASC API key 放進 GitHub secrets。現在那把是 Admin 權限，放進公開 repo 的 secrets（只有 tag push 會用、fork 的 PR 拿不到）風險可接受嗎？替代：CEO 在 App Store Connect → 使用者與存取 → 整合，另建一把 Developer 權限的 key 專供公證，告訴我 gopass 路徑。沒裁決前 CI 出的是「Developer ID 簽但沒公證」的版本（Gatekeeper 第一次開會警告，但 TCC 穩定）。

## 待裁決
- **S-5. 公證用的 ASC API key 要不要放 GitHub secrets？**（見第十輪）
- ~~S-1. 要不要簽開發憑證？~~ 10-26 CEO 開了 Apple Developer，改用 Developer ID（第十輪）。
- **S-2. 這個 POC 要不要進點子漏斗走產品長審？** 目前是 CEO 直接交辦，沒有提案書；市場上 Typeless、Wispr Flow、superwhisper 已經很擠，差異化只有「完全不連外、免費」。

## 檔案
- `Sources/HearMe/Core/`：`Settings`（偏好、app 語氣規則）、`PushToTalk`（按住／點一下狀態機）、`HotkeyMonitor`（CGEvent tap）、`AudioCapture`、`Transcriber`（SpeechAnalyzer）、`Polisher`（FoundationModels 提示詞）、`TextInjector`（剪貼簿＋⌘V）、`History`、`Pipeline`。
- `Sources/HearMe/App/`：`AppDelegate`（選單列）、`HUDPanel`（浮動提示）、`SettingsView`（SwiftUI 設定）、`Main`（CLI 模式）。
- `Tests/HearMeTests/`：純邏輯單元測試。
- `docs/evidence/`：`run-*.txt` 跑出來的逐字稿與整理結果、截圖；`.wav` 不進 git（`make-test-audio.sh` 重產）。
