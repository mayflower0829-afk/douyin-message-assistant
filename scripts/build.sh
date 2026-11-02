#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_ARCH="$(uname -m)"
TASK_DIST="$TASK_ROOT/dist"
TASK_APP="$TASK_DIST/抖音消息助手.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ROOT/.build/module-cache"
swiftc -O -target "$TASK_ARCH-apple-macosx14.0" -module-cache-path "$TASK_ROOT/.build/module-cache" "$TASK_ROOT/Sources/Messaging.swift" "$TASK_ROOT/Sources/SendRate.swift" "$TASK_ROOT/Sources/Schedule.swift" "$TASK_ROOT/Sources/main.swift" -o "$TASK_APP/Contents/MacOS/MessageAssistant"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MessageAssistant</string>
<key>CFBundleIdentifier</key><string>local.douyin.messageassistant</string>
<key>CFBundleName</key><string>抖音消息助手</string>
<key>CFBundleDisplayName</key><string>抖音消息助手</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>3.1.1</string>
<key>CFBundleShortVersionString</key><string>3.1.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TASK_APP"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_DIST/douyin-message-assistant-macos-$TASK_ARCH.zip"
printf '%s\n' "$TASK_APP"
