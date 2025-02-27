#!/bin/bash

# Android icon generation script

# Source icon file (high resolution version)
SOURCE_ICON="../../macOS Icon Design Template (1).png"  # Using the largest template for Android

# Android icon densities and sizes
# Format: density_name:size
DENSITIES=(
  "mdpi:48"
  "hdpi:72"
  "xhdpi:96"
  "xxhdpi:144"
  "xxxhdpi:192"
)

echo "Generating Android launcher icons..."

# Process each density
for density in "${DENSITIES[@]}"; do
  # Split the density and size
  IFS=':' read -r name size <<< "$density"
  
  # Target directory
  TARGET_DIR="app/src/main/res/mipmap-$name"
  
  # Ensure the directory exists
  mkdir -p "$TARGET_DIR"
  
  echo "Generating $name icon ($size x $size)..."
  
  # Generate the icon
  sips -z $size $size "$SOURCE_ICON" --out "$TARGET_DIR/launcher_icon.png"
done

echo "Android icon generation complete!"
echo "Icons have been placed in the mipmap directories." 