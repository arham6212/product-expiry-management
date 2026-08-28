import 'dart:developer' as developer;

class AppLogger {
  AppLogger._();

  static final instance = AppLogger._();

  void info(String message) {
    developer.log(message, name: 'expiry_manager', level: 800);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'expiry_manager',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error(String message, {required Object error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'expiry_manager',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
