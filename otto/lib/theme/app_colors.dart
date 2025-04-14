import 'package:flutter/material.dart';

/// App color constants used throughout the application
class AppColors {
  // Base colors
  static const primary = Color(0xFF7C3AED);  // Rich purple
  static const secondary = Color(0xFF6366F1); // Indigo
  static const accent = Color(0xFF818CF8);    // Light indigo

  // Base Semantic colors - can be used directly if consistent
  static const error = Color(0xFFEF4444);      // Red
  static const warning = Color(0xFFF59E0B);    // Amber
  static const success = Color(0xFF10B981);    // Emerald
  static const info = Color(0xFF3B82F6);       // Blue

  // Specific constants that might not fit into ColorScheme easily
  // (Use sparingly, prefer Theme.of(context) when possible)
  static const selectionHandle = Color(0xFF7C3AED); // Primary color for handles

  // --- Colors below are now handled by ColorScheme in ThemeProvider ---
  // static const surface = Color(0xFF1E1E2E);
  // static const surfaceLight = Color(0xFF2A2A3F);
  // static const surfaceDark = Color(0xFF15151E);
  // static const background = Color(0xFF0F0F17);
  // static const backgroundAlt = Color(0xFF1A1A27);
  // static const userMessage = Colors.white;
  // static const userMessageBg = Color(0xFF2A2A3F);
  // static const assistantMessageBg = Color(0xFF1E1E2E);
  // static const onPrimary = Colors.white;
  // static const onSurface = Colors.white;
  // static const onSurfaceMedium = Color(0xBBFFFFFF);
  // static const onSurfaceDisabled = Color(0x61FFFFFF);
  // static const onBackground = Colors.white;
  // static const inputBackground = Color(0xFF1E1E2E);
  // static const inputBorder = Color(0xFF2A2A3F);
  // static const inputPlaceholder = Color(0x99FFFFFF);
  // static const scrollbarThumb = Color(0x33FFFFFF);
  // static const scrollbarThumbHover = Color(0x66FFFFFF);
  // static const selection = Color(0x337C3AED);

  // --- Gradients below are now handled by ColorScheme/component themes ---
  // static const primaryGradient = LinearGradient(...);
  // static const backgroundGradient = LinearGradient(...);
} 