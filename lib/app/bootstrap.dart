import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/app_environment.dart';
import '../core/logging/app_logger.dart';
import 'expiry_management_app.dart';

void bootstrap(AppEnvironment environment) {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLogger.instance.error(
          'Unhandled Flutter framework error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        AppLogger.instance.error('Unhandled platform error', error: error, stackTrace: stackTrace);
        return true;
      };

      ErrorWidget.builder = (details) {
        if (kDebugMode) {
          return ErrorWidget(details.exception);
        }
        return const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Something went wrong. Please restart the app.')),
        );
      };

      runApp(ExpiryManagementApp(environment: environment));
    },
    (error, stackTrace) {
      AppLogger.instance.error(
        'Unhandled asynchronous error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}
