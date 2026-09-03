import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';
import 'package:product_expiry_management/core/error/app_exception.dart';

const supabaseUrl = 'https://project.supabase.co';
const supabasePublishableKey = 'sb_publishable_test-key';

void main() {
  group('AppEnvironment', () {
    test('parses a configured staging environment', () {
      final environment = AppEnvironment.parse(
        flavor: 'staging',
        apiBaseUrl: 'https://api.example.test',
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
      );

      expect(environment.flavor, AppFlavor.staging);
      expect(environment.apiBaseUrl, Uri.parse('https://api.example.test'));
      expect(environment.hasApiConfiguration, isTrue);
      expect(environment.supabaseUrl, Uri.parse(supabaseUrl));
      expect(environment.supabasePublishableKey, supabasePublishableKey);
      expect(environment.enableStorefront, isFalse);
    });

    test('allows an optional API URL to remain unconfigured', () {
      final environment = AppEnvironment.parse(
        flavor: 'development',
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
      );

      expect(environment.flavor, AppFlavor.development);
      expect(environment.apiBaseUrl, isNull);
      expect(environment.hasApiConfiguration, isFalse);
    });

    test('rejects an unknown flavor', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'preview',
          supabaseUrl: supabaseUrl,
          supabasePublishableKey: supabasePublishableKey,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a relative API URL', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'production',
          apiBaseUrl: '/api',
          supabaseUrl: supabaseUrl,
          supabasePublishableKey: supabasePublishableKey,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-HTTP API URL', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'production',
          apiBaseUrl: 'mailto:ops@example.test',
          supabaseUrl: supabaseUrl,
          supabasePublishableKey: supabasePublishableKey,
        ),
        throwsArgumentError,
      );
    });

    test('reports every missing required Supabase variable', () {
      expect(
        () => AppEnvironment.parse(flavor: 'development'),
        throwsA(
          isA<ConfigurationException>()
              .having(
                (error) => error.message,
                'message',
                contains('SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY'),
              )
              .having(
                (error) => error.message,
                'run guidance',
                contains('--dart-define-from-file=config/env.local.json'),
              ),
        ),
      );
    });

    test('rejects an invalid Supabase URL', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'development',
          supabaseUrl: 'project.supabase.co',
          supabasePublishableKey: supabasePublishableKey,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a server-only Supabase secret key', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'development',
          supabaseUrl: supabaseUrl,
          supabasePublishableKey: 'sb_secret_server-only',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('defaults the production storefront to disabled', () {
      final environment = AppEnvironment.parse(
        flavor: 'production',
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
      );

      expect(environment.enableStorefront, isFalse);
    });

    test('enables the storefront only when explicitly true', () {
      final enabled = AppEnvironment.parse(
        flavor: 'production',
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
        enableStorefront: 'true',
      );
      final disabled = AppEnvironment.parse(
        flavor: 'development',
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
        enableStorefront: 'false',
      );

      expect(enabled.enableStorefront, isTrue);
      expect(disabled.enableStorefront, isFalse);
    });

    test('rejects an invalid storefront flag', () {
      expect(
        () => AppEnvironment.parse(
          flavor: 'production',
          supabaseUrl: supabaseUrl,
          supabasePublishableKey: supabasePublishableKey,
          enableStorefront: 'yes',
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            'ENABLE_STOREFRONT must be either true or false.',
          ),
        ),
      );
    });
  });
}
