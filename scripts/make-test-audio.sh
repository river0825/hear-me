#!/bin/zsh
# Generate test clips with the system TTS so the pipeline can be exercised on a Mac without a microphone.
set -euo pipefail
OUT="${1:-$(builtin cd "$(dirname "$0")/.." && pwd)/docs/evidence}"
mkdir -p "$OUT"
say -v Meijia --data-format=LEI16@16000 -o "$OUT/zh-correction.wav" "嗯 我明天 呃 明天下午三點 不對 四點 要跟客戶開會 你幫我記一下"
say -v Meijia --data-format=LEI16@16000 -o "$OUT/zh-list.wav" "這次發版要做三件事 第一 更新登入頁 第二 修掉那個 嗯 那個閃退的問題 第三 寫 release notes"
say -v Meijia --data-format=LEI16@16000 -o "$OUT/zh-dict.wav" "請幫我把 IronNote 的訓練記錄匯出 然後傳到拆招的測試伺服器"
say -v Samantha --data-format=LEI16@16000 -o "$OUT/en-filler.wav" "um so I think we should, uh, ship the login page first and then, you know, fix the crash"
echo "clips in $OUT"
