#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_BUNDLE="$ROOT_DIR/dist/Clippy.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
ICONSET_DIR="$BUILD_DIR/Clippy.iconset"
ICON_PATH="$BUILD_DIR/Clippy.icns"
MENUBAR_LOGO="$BUILD_DIR/ClippyMenuBar.pdf"

cd "$ROOT_DIR"
if [[ -n "${MACOS_SDK_PATH:-}" ]]; then
    swift build --configuration release --sdk "$MACOS_SDK_PATH"
else
    swift build --configuration release
fi

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/release/Clippy" "$CONTENTS_DIR/MacOS/Clippy"
swift "$ROOT_DIR/Scripts/GenerateAppIcon.swift" "$ROOT_DIR/Assets/ClippyAppIconSource.png" "$ICONSET_DIR"
iconutil --convert icns "$ICONSET_DIR" --output "$ICON_PATH"
rm -f "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ICON_PATH" "$CONTENTS_DIR/Resources/ClippyAppIcon.icns"
swift "$ROOT_DIR/Scripts/GenerateMenuBarLogo.swift" "$ROOT_DIR/Assets/ClippyAppIconSource.png" "$MENUBAR_LOGO"
cp "$MENUBAR_LOGO" "$CONTENTS_DIR/Resources/ClippyMenuBar.pdf"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Clippy</string>
    <key>CFBundleIconFile</key>
    <string>ClippyAppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.clippy.clipboard</string>
    <key>CFBundleName</key>
    <string>Clippy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
codesign --force --sign - "$APP_BUNDLE"
printf 'Built app: %s\n' "$APP_BUNDLE"
