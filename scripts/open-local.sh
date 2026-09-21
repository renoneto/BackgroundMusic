#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink "${BASH_SOURCE[0]}" || true)"
if [[ -z "$script_path" ]]; then
  script_path="${BASH_SOURCE[0]}"
fi

repo_dir="$(cd "$(dirname "$script_path")/.." && pwd)"
cd "$repo_dir"

xcodebuild \
  -project BGMApp/BGMApp.xcodeproj \
  -scheme "Background Music" \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$repo_dir/DerivedData/Build/Products/Debug/Background Music.app"
osascript -e 'tell application "Background Music" to quit' 2>/dev/null || true
open "$app_path"
