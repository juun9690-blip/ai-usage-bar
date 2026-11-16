#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -m)" != arm64 ]; then
  echo 'This release bundles an Apple Silicon connector. Build on an arm64 Mac.' >&2
  exit 1
fi
bash Scripts/build.sh
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHIVE="AI-Usage-${APP_VERSION}-macos-arm64.zip"
codesign --verify --deep --strict 'dist/AI Usage.app'
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc 'dist/AI Usage.app' "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Packaged: %s\n' "dist/$ARCHIVE"
