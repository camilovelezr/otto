import 'package:flutter/material.dart';

/// AppSpacing
/// 
/// A utility class that defines standardized spacing values throughout the app.
/// These values are designed to create a consistent visual hierarchy and rhythm.
class AppSpacing {
  AppSpacing._(); // Private constructor to prevent instantiation
  
  // Primary spacing constants - REDUCED to eliminate excessive whitespace
  static const double blockSpacing = 5.0;     // Major section breaks and between UI components (reduced from 16.0)
  static const double headerBottomSpacing = 3.0; // Spacing after headers/section titles (reduced from 12.0)
  static const double paragraphSpacing = 3.5;  // Separation between text blocks (reduced from 10.0)
  static const double inlineSpacing = 3.0;     // Moderate separation between related elements (reduced from 8.0)
  static const double listItemSpacing = 1.5;   // Tight spacing between sequence items (reduced from 4.0)

  // Additional semantic spacings based on primary constants
  static const double screenPadding = blockSpacing;
  static const double cardPadding = inlineSpacing;
  static const double inputFieldSpacing = paragraphSpacing;
  static const double buttonGroupSpacing = inlineSpacing;
  static const double iconSpacing = listItemSpacing;
  
  // === Add Missing Spacing Constants ===
  static const double verticalPaddingSmall = 4.0; // Small vertical padding
  static const double inlineSpacingSmall = 4.0;   // Small horizontal padding
  static const double pagePaddingHorizontal = 16.0; // Standard page horizontal padding
  
  // === Add Missing Border Radius Constants ===
  static const double borderRadiusSmall = 4.0;    // For small elements, tags
  static const double borderRadiusMedium = 8.0;   // Standard radius for cards, inputs
  static const double borderRadiusLarge = 12.0;   // For larger containers, dialogs
  static const double borderRadiusXLarge = 16.0;  // For prominent elements
  
  // For creating dynamic, scaled spacing
  static double scale(double value, double factor) => value * factor;
  
  // Helper methods for EdgeInsets
  static EdgeInsets all(double value) => EdgeInsets.all(value);
  static EdgeInsets horizontal(double value) => EdgeInsets.symmetric(horizontal: value);
  static EdgeInsets vertical(double value) => EdgeInsets.symmetric(vertical: value);
  
  // Common EdgeInsets patterns
  static const EdgeInsets screenInsets = EdgeInsets.all(blockSpacing);
  static const EdgeInsets cardInsets = EdgeInsets.all(inlineSpacing);
  static const EdgeInsets listItemInsets = EdgeInsets.symmetric(
    vertical: listItemSpacing,
    horizontal: inlineSpacing,
  );
  static const EdgeInsets formFieldInsets = EdgeInsets.only(
    bottom: paragraphSpacing,
  );
  
  // Spacer widgets for quick use in Column/Row
  static const SizedBox blockSpacer = SizedBox(height: blockSpacing, width: blockSpacing);
  static const SizedBox headerSpacer = SizedBox(height: headerBottomSpacing, width: headerBottomSpacing);
  static const SizedBox paragraphSpacer = SizedBox(height: paragraphSpacing, width: paragraphSpacing);
  static const SizedBox inlineSpacer = SizedBox(height: inlineSpacing, width: inlineSpacing);
  static const SizedBox listItemSpacer = SizedBox(height: listItemSpacing, width: listItemSpacing);
  
  // Responsive spacing that adjusts based on screen size
  static double responsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) {
      return baseSpacing * 1.15; // Slightly larger spacing on desktop (reduced from 1.25)
    } else if (screenWidth < 600) {
      return baseSpacing * 0.85; // Tighter spacing on mobile
    }
    return baseSpacing; // Default tablet/medium size spacing
  }
} 