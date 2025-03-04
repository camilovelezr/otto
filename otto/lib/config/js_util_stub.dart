/// Stub implementation of js_util functions for non-web platforms
/// This file is only used when the app is not running on web

/// Stub implementation of callMethod
dynamic callMethod(dynamic obj, String method, List<dynamic> args) {
  throw UnsupportedError('callMethod is only available on web platforms');
}

/// Stub implementation of promiseToFuture
Future<T> promiseToFuture<T>(dynamic jsPromise) {
  throw UnsupportedError('promiseToFuture is only available on web platforms');
}

/// Stub implementation of globalThis
dynamic get globalThis {
  throw UnsupportedError('globalThis is only available on web platforms');
} 