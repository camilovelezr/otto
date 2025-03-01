#!/bin/bash

# Comprehensive icon generation script for both macOS and Android

echo "===== Aithena Icon Generator ====="
echo "Generating icons for both macOS and Android platforms"
echo "===================================="

# Source icon files with parent directory path
LARGE_ICON="../macOS Icon Design Template (1).png"  # For larger icons
MEDIUM_ICON="../macOS Icon Design Template (2).png"  # For medium icons
SMALL_ICON="../macOS Icon Design Template (3).png"  # For smallest icons

# Check if source files exist
if [ ! -f "$LARGE_ICON" ]; then
  echo "Error: $LARGE_ICON not found!"
  exit 1
fi

if [ ! -f "$MEDIUM_ICON" ]; then
  echo "Error: $MEDIUM_ICON not found!"
  exit 1
fi

if [ ! -f "$SMALL_ICON" ]; then
  echo "Error: $SMALL_ICON not found!"
  exit 1
fi

echo ""
echo "===== Generating macOS Icons ====="

# macOS icon generation
MACOS_ICON_PATH="macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MACOS_ICON_PATH"

# Generate smallest icon (16x16)
echo "Generating 16x16 icon from $SMALL_ICON..."
sips -z 16 16 "$SMALL_ICON" --out "$MACOS_ICON_PATH/app_icon_16.png"

# Generate medium icons (32x32, 64x64)
echo "Generating medium icons from $MEDIUM_ICON..."
sips -z 32 32 "$MEDIUM_ICON" --out "$MACOS_ICON_PATH/app_icon_32.png"
sips -z 64 64 "$MEDIUM_ICON" --out "$MACOS_ICON_PATH/app_icon_64.png"

# Generate large icons (128x128, 256x256, 512x512, 1024x1024)
echo "Generating large icons from $LARGE_ICON..."
sips -z 128 128 "$LARGE_ICON" --out "$MACOS_ICON_PATH/app_icon_128.png"
sips -z 256 256 "$LARGE_ICON" --out "$MACOS_ICON_PATH/app_icon_256.png"
sips -z 512 512 "$LARGE_ICON" --out "$MACOS_ICON_PATH/app_icon_512.png"
sips -z 1024 1024 "$LARGE_ICON" --out "$MACOS_ICON_PATH/app_icon_1024.png"

echo "macOS icon generation complete!"

echo ""
echo "===== Generating Android Icons ====="

# Android icon densities and sizes
# Format: density_name:size
DENSITIES=(
  "mdpi:48"
  "hdpi:72"
  "xhdpi:96"
  "xxhdpi:144"
  "xxxhdpi:192"
)

# Process each density
for density in "${DENSITIES[@]}"; do
  # Split the density and size
  IFS=':' read -r name size <<< "$density"
  
  # Target directory
  TARGET_DIR="android/app/src/main/res/mipmap-$name"
  
  # Ensure the directory exists
  mkdir -p "$TARGET_DIR"
  
  echo "Generating $name icon ($size x $size)..."
  
  # Generate the icon
  sips -z $size $size "$LARGE_ICON" --out "$TARGET_DIR/launcher_icon.png"
done

echo "Android icon generation complete!"
echo ""
echo "===== All Icons Generated Successfully ====="
echo "macOS icons: $MACOS_ICON_PATH"
echo "Android icons: android/app/src/main/res/mipmap-*" 