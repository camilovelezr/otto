import 'package:flutter/material.dart';

/// AppSpacing
/// 
/// A utility class that defines standardized spacing values throughout the app.
/// These values are designed to create a consistent visual hierarchy and rhythm.
class AppSpacing {
  AppSpacing._(); // Private constructor to prevent instantiation
  
  // Primary spacing constants
  static const double blockSpacing = 16.0;     // Major section breaks and between UI components
  static const double headerBottomSpacing = 12.0; // Spacing after headers/section titles
  static const double paragraphSpacing = 10.0;  // Separation between text blocks
  static const double inlineSpacing = 8.0;     // Moderate separation between related elements
  static const double listItemSpacing = 4.0;   // Tight spacing between sequence items

  // Additional semantic spacings based on primary constants
  static const double screenPadding = blockSpacing;
  static const double cardPadding = inlineSpacing;
  static const double inputFieldSpacing = paragraphSpacing;
  static const double buttonGroupSpacing = inlineSpacing;
  static const double iconSpacing = listItemSpacing;
  
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
      return baseSpacing * 1.25; // Larger spacing on desktop
    } else if (screenWidth < 600) {
      return baseSpacing * 0.85; // Tighter spacing on mobile
    }
    return baseSpacing; // Default tablet/medium size spacing
  }
} 