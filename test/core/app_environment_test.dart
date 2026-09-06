import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';
import 'package:product_expiry_management/core/error/app_exception.dart';

const supabaseUrl = 'https://project.supabase.co';
const supabasePublishableKey = 'sb_publishable_test-key';

void main() {
  group('AppEnvironment', () {
    test('accepts an explicit safe production build contract', () {
      final environment = AppEnvironment.fromBuildConfig({
        'APP_ENV': 'production',
        'SUPABASE_URL': supabaseUrl,
        'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
        'PRODUCTION_SUPABASE_PROJECT_REF': 'project',
        'ENABLE_STOREFRONT': 'false',
      });

      expect(environment.flavor, AppFlavor.production);
      expect(environment.enableStorefront, isFalse);
    });

    test('rejects a production build contract with missing values', () {
      expect(
        () => AppEnvironment.fromBuildConfig({
          'APP_ENV': 'production',
          'SUPABASE_URL': supabaseUrl,
          'PRODUCTION_SUPABASE_PROJECT_REF': 'project',
          'ENABLE_STOREFRONT': 'false',
        }),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            'SUPABASE_PUBLISHABLE_KEY must be an explicit non-empty string.',
          ),
        ),
      );
    });

    test('requires APP_ENV instead of defaulting a build contract', () {
      expect(
        () => AppEnvironment.fromBuildConfig({
          'SUPABASE_URL': supabaseUrl,
          'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
          'ENABLE_STOREFRONT': 'false',
        }),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            'APP_ENV must be an explicit non-empty string.',
          ),
        ),
      );
    });

    test('rejects an invalid production client key', () {
      expect(
        () => AppEnvironment.fromBuildConfig({
          'APP_ENV': 'production',
          'SUPABASE_URL': supabaseUrl,
          'SUPABASE_PUBLISHABLE_KEY': 'not-a-supabase-key',
          'PRODUCTION_SUPABASE_PROJECT_REF': 'project',
          'ENABLE_STOREFRONT': 'false',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects unsafe production storefront enablement', () {
      expect(
        () => AppEnvironment.fromBuildConfig({
          'APP_ENV': 'production',
          'SUPABASE_URL': supabaseUrl,
          'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
          'PRODUCTION_SUPABASE_PROJECT_REF': 'project',
          'ENABLE_STOREFRONT': 'true',
        }),
        throwsA(
          isA<ConfigurationException>().having(
            (error) => error.message,
            'message',
            'ENABLE_STOREFRONT=true requires STOREFRONT_SCHEMA_AVAILABLE=true.',
          ),
        ),
      );
    });

    test('allows production storefront only with explicit schema acknowledgement', () {
      final environment = AppEnvironment.fromBuildConfig({
        'APP_ENV': 'production',
        'SUPABASE_URL': supabaseUrl,
        'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
        'PRODUCTION_SUPABASE_PROJECT_REF': 'project',
        'ENABLE_STOREFRONT': 'true',
        'STOREFRONT_SCHEMA_AVAILABLE': 'true',
      });

      expect(environment.enableStorefront, isTrue);
    });

    test('rejects a production URL that does not match the explicit project ref', () {
      expect(
        () => AppEnvironment.fromBuildConfig({
          'APP_ENV': 'production',
          'SUPABASE_URL': supabaseUrl,
          'SUPABASE_PUBLISHABLE_KEY': supabasePublishableKey,
          'PRODUCTION_SUPABASE_PROJECT_REF': 'different-project',
          'ENABLE_STOREFRONT': 'false',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

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
                contains('--dart-define-from-file=config/env.<environment>.local.json'),
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
