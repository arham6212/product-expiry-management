import 'dart:convert';
import 'dart:io';

import 'package:product_expiry_management/core/config/app_environment.dart';

Future<void> main(List<String> arguments) async {
  final checkOnly = arguments.firstOrNull == '--check';
  final configArguments = checkOnly ? arguments.skip(1).toList() : arguments;
  if (configArguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/build_pilot_apk.dart [--check] '
      'config/env.production.local.json',
    );
    exitCode = 64;
    return;
  }

  final configPath = configArguments.single;
  try {
    final decoded = jsonDecode(await File(configPath).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The configuration root must be a JSON object.');
    }
    final environment = AppEnvironment.fromBuildConfig(decoded);
    if (environment.flavor != AppFlavor.production) {
      throw const FormatException('APP_ENV must be production for a pilot APK.');
    }
  } on Object catch (error) {
    stderr.writeln('Production configuration rejected: $error');
    exitCode = 64;
    return;
  }

  stdout.writeln('Production configuration accepted.');
  if (checkOnly) return;

  final process = await Process.start('flutter', [
    'build',
    'apk',
    '--release',
    '--dart-define-from-file=$configPath',
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await process.exitCode;
}
