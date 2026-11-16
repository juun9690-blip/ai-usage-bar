#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tools
URL='https://github.com/steipete/CodexBar/releases/download/v0.82.0/CodexBarCLI-v0.82.0-macos-arm64.tar.gz'
curl -fL "$URL" -o Tools/codexbar.tar.gz
EXPECTED='5e6d922fbebbd41a748bc906500740529265e65afbc7ffd2ce8c8794fc5edf76'
ACTUAL=$(shasum -a 256 Tools/codexbar.tar.gz | cut -d ' ' -f 1)
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo 'Connector checksum mismatch' >&2
  exit 1
fi
tar -xzf Tools/codexbar.tar.gz -C Tools
