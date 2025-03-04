/// A stub implementation for Platform to be used in web environments
/// This provides a simple API-compatible implementation with the dart:io Platform
/// class that is used in mobile/desktop environments

class Platform {
  static const String _operatingSystem = 'web';
  
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
  
  static bool get isWeb => true;
  
  static String get operatingSystem => _operatingSystem;
  
  static String get operatingSystemVersion => 'web';
  
  // Add other platform properties as needed
} 