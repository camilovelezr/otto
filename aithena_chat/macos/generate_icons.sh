#!/bin/bash

# Directory containing the AppIcon.appiconset
ICON_SET_PATH="Runner/Assets.xcassets/AppIcon.appiconset"

# Source icon files for different size ranges
LARGE_ICON="macOS Icon Design Template (1).png"  # For larger icons
MEDIUM_ICON="macOS Icon Design Template (2).png"  # For medium icons
SMALL_ICON="macOS Icon Design Template (3).png"  # For smallest icons

# Make sure the directory exists
mkdir -p "${ICON_SET_PATH}"

# Generate smallest icon (16x16)
echo "Generating 16x16 icon from ${SMALL_ICON}..."
sips -z 16 16 "${SMALL_ICON}" --out "${ICON_SET_PATH}/app_icon_16.png"

# Generate medium icons (32x32, 64x64)
echo "Generating medium icons from ${MEDIUM_ICON}..."
sips -z 32 32 "${MEDIUM_ICON}" --out "${ICON_SET_PATH}/app_icon_32.png"
sips -z 64 64 "${MEDIUM_ICON}" --out "${ICON_SET_PATH}/app_icon_64.png"

# Generate large icons (128x128, 256x256, 512x512, 1024x1024)
echo "Generating large icons from ${LARGE_ICON}..."
sips -z 128 128 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_128.png"
sips -z 256 256 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_256.png"
sips -z 512 512 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_512.png"
sips -z 1024 1024 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_1024.png"

echo "Icon generation complete!"
echo "Icons have been placed in ${ICON_SET_PATH}" 