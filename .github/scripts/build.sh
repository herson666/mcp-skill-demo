#!/usr/bin/env bash
# .github/scripts/build.sh — universal build step for github-multiplatform-packager
# Called by GitHub Actions workflow with env: STACK PLATFORM VERSION
set -euo pipefail

STACK="${STACK:?}"      # python / electron / rust / go / node / node-cli / flutter / java / dotnet / android-native / ios-native
PLATFORM="${PLATFORM:?}"  # windows / macos / linux / android / ios
VERSION="${VERSION:-0.0.1}"

log() { printf '[build] [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---- mkdir -p dist/ ----
mkdir -p dist

case "$STACK" in
  python)
    log "Building python app for $PLATFORM v$VERSION"
    pip install --disable-pip-version-check pyinstaller PySide6 2>&1 | tail -5 || pip install pyinstaller PySide6

    # Choose entry point: main.py (preferred), else any *.py
    ENTRY="main.py"
    [ -f "$ENTRY" ] || ENTRY=$(ls ./*.py 2>/dev/null | head -1)
    [ -z "$ENTRY" ] && { log "No .py entry found"; ls -la; exit 1; }
    log "Entry: $ENTRY"

    APP_NAME="${APP_NAME:-hello-app}"

    case "$PLATFORM" in
      windows)
        # windows-latest has PowerShell; we use git-bash-on-Windows.
        # One-file binary via PyInstaller.
        pyinstaller --noconfirm --onefile --clean --name "${APP_NAME}-${VERSION}-windows-x64" "$ENTRY" 2>&1 | tail -30
        ls dist/
        # Create a simple readme as an artifact alongside the exe
        echo "Hello PySide6 $VERSION Windows build" > dist/"${APP_NAME}-${VERSION}-windows-x64.exe.readme"
        ;;
      macos)
        # Homebrew python + pyinstaller. May not produce a real .app but does produce a one-file binary.
        pyinstaller --noconfirm --onefile --clean --name "${APP_NAME}-${VERSION}-macos-universal" "$ENTRY" 2>&1 | tail -30
        ls dist/
        echo "Hello PySide6 $VERSION macOS build" > dist/"${APP_NAME}-${VERSION}-macos-universal.readme"
        # Also build a .app bundle
        pyinstaller --noconfirm --windowed --clean --name "${APP_NAME}-${VERSION}-macos-app" "$ENTRY" 2>&1 | tail -15 || true
        # Create .dmg if hdiutil available (macos-latest)
        if command -v hdiutil >/dev/null 2>&1; then
          mkdir -p dist/dmg
          [ -d "dist/${APP_NAME}-${VERSION}-macos-app.app" ] && cp -r "dist/${APP_NAME}-${VERSION}-macos-app.app" dist/dmg/
          hdiutil create -volname "${APP_NAME}-${VERSION}" -srcfolder dist/dmg -ov -format UDZO "dist/${APP_NAME}-${VERSION}-macos-universal.dmg" || true
        fi
        ls dist/
        ;;
      linux)
        pyinstaller --noconfirm --onefile --clean --name "${APP_NAME}-${VERSION}-linux-x86_64" "$ENTRY" 2>&1 | tail -30
        ls dist/
        echo "Hello PySide6 $VERSION Linux build" > dist/"${APP_NAME}-${VERSION}-linux-x86_64.readme"
        # Wrap as a minimal AppImage-ish shell archive artifact (we just rename the binary with the AppImage extension for now)
        # A real AppImage would need linuxdeploy / appimagetool — keep it simple.
        cp dist/"${APP_NAME}-${VERSION}-linux-x86_64" dist/"${APP_NAME}-${VERSION}-linux-x86_64.AppImage" || true
        ;;
      *)
        log "Unsupported PLATFORM=$PLATFORM for python stack; falling back to source tarball"
        tar -czf "dist/${APP_NAME}-${VERSION}-${PLATFORM}-src.tar.gz" ./*.py ./requirements.txt ./pyproject.toml 2>/dev/null || true
        ;;
    esac
    ;;

  *)
    log "Stack $STACK on $PLATFORM not fully implemented; producing a source dist artifact so release job has something to upload"
    tar -czf "dist/${STACK:-app}-${VERSION}-${PLATFORM}-src.tar.gz" . 2>/dev/null || true
    ;;
esac

echo ""
log "Artifacts:"
ls -lh dist/ || true
