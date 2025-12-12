#!/bin/bash

# Configuration
APP_NAME="WhisperWrap"
OUTPUT_DIR="."
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
EXECUTABLE_NAME="WhisperWrap"
ICON_SOURCE="Sources/WhisperWrap/Resources/AppIcon.appiconset/icon_1024x1024.png"

# Build
echo "Building Release Configuration..."
swift build -c release

# Check if build succeeded
if [ $? -ne 0 ]; then
    echo "Build failed."
    exit 1
fi

# Create App Bundle Structure
echo "Creating Bundle Structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy Executable
echo "Copying Executable..."
cp ".build/release/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Generate Icon
if [ -f "$ICON_SOURCE" ]; then
    echo "Generating App Icon..."
    ICONSET_DIR="${APP_BUNDLE}/Contents/Resources/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Convert source to proper PNG (handles JPEG with .png extension)
    TEMP_PNG="/tmp/whisper_wrap_icon_temp.png"
    sips -s format png "$ICON_SOURCE" --out "$TEMP_PNG" > /dev/null 2>&1
    
    # Generate all required icon sizes
    sips -z 16 16     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$TEMP_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1
    
    rm -f "$TEMP_PNG"
    
    # Convert to .icns
    iconutil -c icns "$ICONSET_DIR" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"

    ICON_KEY="<key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    echo "Warning: Icon source not found at $ICON_SOURCE"
    ICON_KEY=""
fi

# Create Info.plist
echo "Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.akeslo.WhisperWrap</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperWrap needs access to your microphone to transcribe your dictation.</string>
    ${ICON_KEY}
</dict>
</plist>
EOF

# Code signing
echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "App Bundle created at ${APP_BUNDLE}"
