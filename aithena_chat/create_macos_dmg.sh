#!/bin/bash

# Exit on error
set -e

# Configuration
APP_NAME="Otto"
DMG_NAME="${APP_NAME}_Installer"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="build/macos/${DMG_NAME}.dmg"
TMP_DMG_PATH="build/macos/${DMG_NAME}_tmp.dmg"
VOLUME_NAME="${APP_NAME}"
DMG_SIZE="300m"  # Increased size to accommodate background
RESOURCES_DIR="build/macos/dmg_resources"
BACKGROUND_FILE="${RESOURCES_DIR}/background.png"
DS_STORE_FILE="${RESOURCES_DIR}/DS_Store"

# Create resources directory
mkdir -p "${RESOURCES_DIR}"

# Check if the app exists
if [ ! -d "$APP_PATH" ]; then
  echo "Error: Application not found at $APP_PATH"
  echo "Please make sure to run 'flutter build macos --release' first."
  exit 1
fi

# Create the build directory if it doesn't exist
mkdir -p "build/macos"

# Create a beautiful background image
echo "Creating background image..."
# Purple background with logo - adjust colors as needed
cat > "${RESOURCES_DIR}/background.svg" << EOF
<svg width="600" height="400" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#5B21B6;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#A78BFA;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="600" height="400" fill="url(#grad)" rx="10" ry="10" />
  <text x="300" y="70" font-family="Arial" font-size="48" text-anchor="middle" fill="white">${APP_NAME}</text>
  <text x="300" y="110" font-family="Arial" font-size="20" text-anchor="middle" fill="white">Drag to Applications folder to install</text>
  <path d="M150,200 L450,200" stroke="white" stroke-width="2" stroke-dasharray="10,5" />
  <circle cx="150" cy="200" r="10" fill="white" />
  <text x="150" y="240" font-family="Arial" font-size="18" text-anchor="middle" fill="white">App</text>
  <circle cx="450" cy="200" r="10" fill="white" />
  <text x="450" y="240" font-family="Arial" font-size="18" text-anchor="middle" fill="white">Applications</text>
</svg>
EOF

# Convert SVG to PNG using ImageMagick
magick "${RESOURCES_DIR}/background.svg" "${BACKGROUND_FILE}"

# Remove any existing DMG
if [ -f "$DMG_PATH" ]; then
  echo "Removing existing DMG: $DMG_PATH"
  rm "$DMG_PATH"
fi

if [ -f "$TMP_DMG_PATH" ]; then
  echo "Removing existing temporary DMG: $TMP_DMG_PATH"
  rm "$TMP_DMG_PATH"
fi

# Create a temporary DMG
echo "Creating temporary DMG..."
hdiutil create -size $DMG_SIZE -fs HFS+ -volname "$VOLUME_NAME" "$TMP_DMG_PATH"

# Mount the temporary DMG
echo "Mounting temporary DMG..."
MOUNT_POINT="/Volumes/$VOLUME_NAME"
hdiutil attach "$TMP_DMG_PATH"

# Copy the app to the mounted DMG
echo "Copying $APP_NAME.app to the DMG..."
cp -R "$APP_PATH" "$MOUNT_POINT/"

# Create a symbolic link to /Applications
echo "Creating symbolic link to /Applications..."
ln -s /Applications "$MOUNT_POINT/Applications"

# Create the .background directory and copy the background image
echo "Setting up background image..."
mkdir -p "$MOUNT_POINT/.background"
cp "$BACKGROUND_FILE" "$MOUNT_POINT/.background/"

# Create the custom view configuration using AppleScript
echo "Configuring DMG appearance..."
osascript << EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        
        -- Set background
        set the bounds of the container window to {200, 100, 800, 500}
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set icon size of icon view options of container window to 80
        set arrangement of icon view options of container window to not arranged
        set background picture of icon view options of container window to file ".background:background.png"
        
        -- Position application icon and Applications symlink
        set position of item "${APP_NAME}.app" to {150, 200}
        set position of item "Applications" to {450, 200}
        
        -- No longer trying to hide the background folder
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Wait for the finder to update
sleep 2

# Ensure Finder process is closed to save changes
echo "Saving DMG view settings..."
osascript -e 'tell application "Finder" to close windows' || true

# Wait for the copy to complete and sync
echo "Waiting for sync..."
sync

# Unmount the DMG
echo "Unmounting temporary DMG..."
hdiutil detach "$MOUNT_POINT" -force || hdiutil detach "$MOUNT_POINT" -force

# Convert the temporary DMG to the final compressed DMG
echo "Creating final compressed DMG..."
hdiutil convert "$TMP_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

# Clean up temporary files
echo "Cleaning up temporary files..."
rm "$TMP_DMG_PATH"
rm -r "$RESOURCES_DIR"

echo "DMG created successfully: $DMG_PATH"
echo "Installation package is ready for distribution!" 