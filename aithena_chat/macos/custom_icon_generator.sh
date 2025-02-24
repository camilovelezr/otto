#!/bin/bash

# Directory containing the AppIcon.appiconset
ICON_SET_PATH="Runner/Assets.xcassets/AppIcon.appiconset"

# Source icons for different size ranges (using absolute paths)
LARGE_ICON="../../macOS Icon Design Template (1).png"  # Original larger version
SMALL_ICON="../../macOS Icon Design Template (2).png"  # New smaller version

# Make sure the directory exists
mkdir -p "${ICON_SET_PATH}"

# Generate small icons (16, 32, 64) from the smaller template
echo "Generating small icons from ${SMALL_ICON}..."
sips -z 16 16 "${SMALL_ICON}" --out "${ICON_SET_PATH}/app_icon_16.png"
sips -z 32 32 "${SMALL_ICON}" --out "${ICON_SET_PATH}/app_icon_32.png"
sips -z 64 64 "${SMALL_ICON}" --out "${ICON_SET_PATH}/app_icon_64.png"

# Generate large icons (128, 256, 512, 1024) from the larger template
echo "Generating large icons from ${LARGE_ICON}..."
sips -z 128 128 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_128.png"
sips -z 256 256 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_256.png"
sips -z 512 512 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_512.png"
sips -z 1024 1024 "${LARGE_ICON}" --out "${ICON_SET_PATH}/app_icon_1024.png"

echo "Custom icon generation complete!"
echo "Icons have been placed in ${ICON_SET_PATH}" 