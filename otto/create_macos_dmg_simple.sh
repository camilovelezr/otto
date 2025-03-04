#!/bin/bash
# Exit on error
set -e

# App information
APP_NAME="Otto"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}_${VERSION}"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
OUTPUT_DMG_PATH="build/macos/${DMG_NAME}.dmg"

echo "🚀 Building macOS DMG for ${APP_NAME} ${VERSION}"

# Build the Flutter app for macOS if it doesn't exist
if [ ! -d "${APP_PATH}" ]; then
    echo "🔨 Building the app first..."
    flutter clean
    flutter pub get
    flutter build macos --release
fi

# Check if build succeeded
if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Build failed. Could not find ${APP_PATH}"
    exit 1
fi

echo "📦 Creating DMG..."

# Remove any existing DMG file
rm -f "${OUTPUT_DMG_PATH}"

# Create the DMG
hdiutil create -volname "${APP_NAME}" \
               -srcfolder "${APP_PATH}" \
               -ov -format UDZO \
               "${OUTPUT_DMG_PATH}"

# Check if the DMG was created successfully
if [ -f "${OUTPUT_DMG_PATH}" ]; then
    echo "✅ DMG created successfully at ${OUTPUT_DMG_PATH}"
    # Open Finder at the DMG location
    open "$(dirname "${OUTPUT_DMG_PATH}")"
else
    echo "❌ Failed to create DMG"
    exit 1
fi