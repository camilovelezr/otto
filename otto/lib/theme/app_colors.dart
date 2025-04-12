import 'package:flutter/material.dart';

/// App color constants used throughout the application
class AppColors {
  // Base colors
  static const primary = Color(0xFF7C3AED);  // Rich purple
  static const secondary = Color(0xFF6366F1); // Indigo
  static const accent = Color(0xFF818CF8);    // Light indigo

  // Surface colors
  static const surface = Color(0xFF1E1E2E);        // Deep blue-gray
  static const surfaceLight = Color(0xFF2A2A3F);   // Lighter surface
  static const surfaceDark = Color(0xFF15151E);    // Darker surface

  // Background colors
  static const background = Color(0xFF0F0F17);     // Rich dark background
  static const backgroundAlt = Color(0xFF1A1A27);  // Alternative background

  // Message colors
  static const userMessage = Colors.white;    // White text for user messages
  static const userMessageBg = Color(0xFF2A2A3F);  // Lighter surface for user messages
  static const assistantMessageBg = Color(0xFF1E1E2E); // Dark surface for assistant

  // Text colors
  static const onPrimary = Colors.white;
  static const onSurface = Colors.white;
  static const onSurfaceMedium = Color(0xBBFFFFFF);  // 73% white
  static const onSurfaceDisabled = Color(0x61FFFFFF); // 38% white
  static const onBackground = Colors.white;

  // Semantic colors
  static const error = Color(0xFFEF4444);      // Red
  static const warning = Color(0xFFF59E0B);    // Amber
  static const success = Color(0xFF10B981);    // Emerald
  static const info = Color(0xFF3B82F6);       // Blue

  // Gradients
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),  // Purple
      Color(0xFF6366F1),  // Indigo
    ],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0F0F17),  // Dark background
      Color(0xFF1A1A27),  // Slightly lighter
    ],
  );

  // Input field colors
  static const inputBackground = Color(0xFF1E1E2E);
  static const inputBorder = Color(0xFF2A2A3F);
  static const inputPlaceholder = Color(0x99FFFFFF);  // 60% white

  // Scrollbar colors
  static const scrollbarThumb = Color(0x33FFFFFF);    // 20% white
  static const scrollbarThumbHover = Color(0x66FFFFFF); // 40% white

  // Selection colors
  static const selection = Color(0x337C3AED);  // 20% primary
  static const selectionHandle = Color(0xFF7C3AED);  // Primary
} 