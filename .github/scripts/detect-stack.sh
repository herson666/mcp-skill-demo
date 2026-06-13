#!/usr/bin/env bash
# .github/scripts/detect-stack.sh — output stack detection JSON to stdout
# Called by the "detect" job of the Actions workflow.
set -euo pipefail

RESULT=$(mktemp)
trap 'rm -f "$RESULT"' EXIT

# Start with empty object
jq -n '{}' > "$RESULT"
update() { local tmp; tmp=$(mktemp); jq --arg k "$1" --arg v "$2" '. + {($k): $v}' "$RESULT" > "$tmp" && mv "$tmp" "$RESULT"; }

# ---- 1. flutter ----
if [ -f pubspec.yaml ] && grep -q '^flutter:' pubspec.yaml 2>/dev/null; then
  update stack flutter; update build_tool flutter-cli; update entry_point lib/main.dart
fi

# ---- 2. tauri ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && [ -f src-tauri/tauri.conf.json ]; then
  update stack tauri; update build_tool tauri-cli; update entry_point src-tauri/
fi

# ---- 3. rust ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && [ -f Cargo.toml ]; then
  update stack rust; update build_tool cargo-bundle
  v=$(grep '^version' Cargo.toml | head -1 | sed -E 's/version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
  [ -n "${v:-}" ] && update version "$v"
fi

# ---- 4. go ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && [ -f go.mod ]; then
  update stack go; update build_tool go-build; update entry_point main.go
fi

# ---- 5. java ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && { [ -f pom.xml ] || ls build.gradle* >/dev/null 2>&1; }; then
  update stack java; update build_tool jpackage
  if [ -f pom.xml ]; then update entry_point pom.xml; else update entry_point build.gradle; fi
fi

# ---- 6. dotnet ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && { ls ./*.csproj >/dev/null 2>&1 || ls ./*.sln >/dev/null 2>&1; }; then
  update stack dotnet; update build_tool dotnet-publish; update entry_point "$(ls ./*.csproj 2>/dev/null | head -1 || ls ./*.sln 2>/dev/null | head -1)"
fi

# ---- 7. package.json (node / electron / neutralino) ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && [ -f package.json ]; then
  has_dep() { jq -e --arg d "$1" '[(.dependencies // {}), (.devDependencies // {})] | map(has($d)) | any' package.json >/dev/null 2>&1; }
  if has_dep "electron-builder" || has_dep "electron"; then update stack electron; update build_tool electron-builder
  elif has_dep "@neutralinojs/neu"; then update stack neutralino; update build_tool neutralinojs-cli
  elif has_dep "pkg"; then update stack node-cli; update build_tool pkg
  else update stack node; update build_tool pkg
  fi
  main=$(jq -r '.main // empty' package.json 2>/dev/null || true)
  [ -n "${main:-}" ] && update entry_point "$main" || update entry_point "index.js"
  v=$(jq -r '.version // empty' package.json 2>/dev/null || true)
  [ -n "${v:-}" ] && update version "$v"
fi

# ---- 8. python ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && { [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; }; then
  update stack python; update build_tool pyinstaller
  if [ -f pyproject.toml ]; then
    v=$(grep -E '^version[[:space:]]*=' pyproject.toml | head -1 | sed -E 's/version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    [ -n "${v:-}" ] && update version "$v"
  fi
  update entry_point "main.py"
fi

# ---- 9. ios-native ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && { ls ./*.xcodeproj >/dev/null 2>&1 || ls ./*.xcworkspace >/dev/null 2>&1 || [ -f Podfile ]; }; then
  update stack ios-native; update build_tool xcodebuild
  update entry_point "$(ls ./*.xcodeproj 2>/dev/null | head -1 || ls ./*.xcworkspace 2>/dev/null | head -1)"
fi

# ---- 10. android-native ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ] && [ -d android ] && { [ -f android/app/src/main/AndroidManifest.xml ] || [ -f android/AndroidManifest.xml ]; }; then
  update stack android-native; update build_tool gradle; update entry_point "android/app"
fi

# ---- Version fallback ----
if [ -z "$(jq -r '.version // empty' "$RESULT")" ] && git describe --tags --abbrev=0 >/dev/null 2>&1; then
  v=$(git describe --tags --abbrev=0 | sed 's/^v//'); update version "$v"
fi
[ -z "$(jq -r '.version // empty' "$RESULT")" ] && update version "0.0.1"

# ---- Output ----
if [ -z "$(jq -r '.stack // empty' "$RESULT")" ]; then
  # Unknown → fall back to minimal "node" so the pipeline still produces an artifact.
  echo '{"stack":"unknown","build_tool":"tar","entry_point":".","version":"0.0.1","config_files":[]}'
  exit 0
fi
tmp=$(mktemp); jq '. + {config_files: (.config_files // [])}' "$RESULT" > "$tmp" && mv "$tmp" "$RESULT"
cat "$RESULT"
