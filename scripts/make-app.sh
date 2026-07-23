#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product PromptBoardApp

APP_BUNDLE=dist/PromptBoard.app
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp .build/release/PromptBoardApp "$APP_BUNDLE/Contents/MacOS/PromptBoard"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>PromptBoard</string>
	<key>CFBundleIdentifier</key>
	<string>com.arya.PromptBoard</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>PromptBoard</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# Prefer the stable self-signed identity so macOS keeps the Accessibility grant
# across rebuilds; fall back to ad-hoc if it hasn't been set up on this machine.
SIGNING_IDENTITY="PromptBoard Local Signing"
if security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$SIGNING_IDENTITY" --identifier com.arya.PromptBoard "$APP_BUNDLE"
    echo "Signed with '$SIGNING_IDENTITY' — the Accessibility grant persists across reinstalls."
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "Signed ad-hoc. Run 'make signing-identity' so the Accessibility grant survives future reinstalls."
fi

echo "Built $APP_BUNDLE"
