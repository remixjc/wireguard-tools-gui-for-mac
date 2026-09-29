#!/bin/bash
# 构建 WireGuardTray.app：SwiftPM release 构建 → 组装 .app bundle → ad-hoc 签名
# 用法: ./Scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="WireGuardTray"
VERSION="0.1.0"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
echo "==> binary: $BIN_PATH"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# 应用图标（Assets/AppIcon.icns，由 Assets/AppIcon-source-1024.png 生成）
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
"
else
    ICON_KEY=""
    echo "    (未找到 Assets/AppIcon.icns，跳过图标)"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>WireGuard Tray</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.wireguard-tray.WireGuardTray</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
${ICON_KEY}    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> codesign (ad-hoc)"
# 云同步目录（iCloud/FileProvider）会给文件注入 provenance 等扩展属性，
# codesign 会拒绝；先清理再签名
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "    (codesign skipped)"

echo ""
echo "✅ built: $(pwd)/$APP_DIR"
echo "   运行: open \"$(pwd)/$APP_DIR\""
