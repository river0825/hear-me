#!/bin/zsh
# Publish a notarized Developer ID build from the dev Mac:
#   bundle (Developer ID, hardened runtime) → notarize + staple → zip + sha256 → GitHub Release vX.Y.Z.
# The Release is created before the tag reaches CI, and release.yml then leaves its assets alone.
# Usage: scripts/release-local.sh 0.2.0
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
builtin cd "$ROOT"
VERSION="${1:?usage: $0 <version, e.g. 0.2.0>}"; VERSION="${VERSION#v}"; TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean; commit first" >&2; exit 1; }
git fetch -q --tags origin
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "HEAD is not origin/main; push first" >&2; exit 1; }

HEARME_VERSION="$VERSION" HEARME_BUILD="$(date +%Y%m%d%H%M)" scripts/bundle.sh
SIG="$(codesign -dv --verbose=2 build/HearMe.app 2>&1 || true)"
[[ "$SIG" == *"Authority=Developer ID Application"* ]] || { echo "not signed with Developer ID; refusing to publish" >&2; exit 1; }
scripts/notarize.sh

rm -f build/HearMe.zip build/HearMe.zip.sha256
ditto -c -k --keepParent build/HearMe.app build/HearMe.zip
(builtin cd build && shasum -a 256 HearMe.zip | tee HearMe.zip.sha256)

PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
NOTES="$(mktemp)"
{
  echo "## 變更（${PREV:-起點} → ${TAG}）"
  echo
  git log --no-merges --format='- %s (%h)' ${PREV:+$PREV..}HEAD
  echo
  echo "macOS 26+、Apple Silicon。Apple Developer ID 簽章並經 Apple 公證。解開 HearMe.zip 後把 HearMe.app 放到「應用程式」再開啟；第一次會要「輔助使用」與「麥克風」權限。之後的版本從選單「有新版本…下載並安裝」更新。"
} > "$NOTES"
gh release create "$TAG" build/HearMe.zip build/HearMe.zip.sha256 --target "$(git rev-parse HEAD)" \
  --title "Hear Me $TAG" --notes-file "$NOTES"
rm -f "$NOTES"
git fetch -q --tags origin
gh release view "$TAG" --json url,assets --jq '.url, (.assets[] | "\(.name) \(.size) bytes")'
