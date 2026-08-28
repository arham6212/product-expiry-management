import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('parses a configured staging environment', () {
      final environment = AppEnvironment.parse(
        flavor: 'staging',
        apiBaseUrl: 'https://api.example.test',
      );

      expect(environment.flavor, AppFlavor.staging);
      expect(environment.apiBaseUrl, Uri.parse('https://api.example.test'));
      expect(environment.hasApiConfiguration, isTrue);
    });

    test('allows an unconfigured development environment', () {
      final environment = AppEnvironment.parse(flavor: 'development');

      expect(environment.flavor, AppFlavor.development);
      expect(environment.apiBaseUrl, isNull);
      expect(environment.hasApiConfiguration, isFalse);
    });

    test('rejects an unknown flavor', () {
      expect(() => AppEnvironment.parse(flavor: 'preview'), throwsArgumentError);
    });

    test('rejects a relative API URL', () {
      expect(
        () => AppEnvironment.parse(flavor: 'production', apiBaseUrl: '/api'),
        throwsArgumentError,
      );
    });

    test('rejects a non-HTTP API URL', () {
      expect(
        () => AppEnvironment.parse(flavor: 'production', apiBaseUrl: 'mailto:ops@example.test'),
        throwsArgumentError,
      );
    });
  });
}
