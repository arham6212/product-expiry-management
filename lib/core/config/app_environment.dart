import 'dart:convert';

import '../error/app_exception.dart';

enum AppFlavor { development, staging, production }

class AppEnvironment {
  const AppEnvironment({
    required this.flavor,
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.enableStorefront,
  });

  factory AppEnvironment.fromCompileTime() {
    const flavor = String.fromEnvironment('APP_ENV');
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const productionSupabaseProjectRef = String.fromEnvironment('PRODUCTION_SUPABASE_PROJECT_REF');
    const enableStorefront = String.fromEnvironment('ENABLE_STOREFRONT');
    const storefrontSchemaAvailable = String.fromEnvironment('STOREFRONT_SCHEMA_AVAILABLE');
    return AppEnvironment.parse(
      flavor: flavor,
      apiBaseUrl: apiBaseUrl,
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      productionSupabaseProjectRef: productionSupabaseProjectRef,
      enableStorefront: enableStorefront,
      storefrontSchemaAvailable: storefrontSchemaAvailable,
      requireExplicitProductionValues: true,
    );
  }

  factory AppEnvironment.fromBuildConfig(Map<String, Object?> values) {
    String requiredValue(String name) {
      final value = values[name];
      if (value is! String || value.trim().isEmpty) {
        throw ConfigurationException('$name must be an explicit non-empty string.');
      }
      return value;
    }

    String optionalValue(String name) {
      final value = values[name];
      if (value == null) return '';
      if (value is! String) {
        throw ConfigurationException('$name must be a string when provided.');
      }
      return value;
    }

    return AppEnvironment.parse(
      flavor: requiredValue('APP_ENV'),
      apiBaseUrl: optionalValue('API_BASE_URL'),
      supabaseUrl: requiredValue('SUPABASE_URL'),
      supabasePublishableKey: requiredValue('SUPABASE_PUBLISHABLE_KEY'),
      productionSupabaseProjectRef: optionalValue('PRODUCTION_SUPABASE_PROJECT_REF'),
      enableStorefront: requiredValue('ENABLE_STOREFRONT'),
      storefrontSchemaAvailable: optionalValue('STOREFRONT_SCHEMA_AVAILABLE'),
      requireExplicitProductionValues: true,
    );
  }

  factory AppEnvironment.parse({
    required String flavor,
    String apiBaseUrl = '',
    String supabaseUrl = '',
    String supabasePublishableKey = '',
    String productionSupabaseProjectRef = '',
    String enableStorefront = '',
    String storefrontSchemaAvailable = '',
    bool requireExplicitProductionValues = false,
  }) {
    final parsedFlavor = switch (flavor.trim().toLowerCase()) {
      'development' => AppFlavor.development,
      'staging' => AppFlavor.staging,
      'production' => AppFlavor.production,
      _ => throw ArgumentError.value(
        flavor,
        'flavor',
        'Expected development, staging, or production',
      ),
    };

    final missingSupabaseVariables = <String>[
      if (supabaseUrl.trim().isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.trim().isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    ];
    if (missingSupabaseVariables.isNotEmpty) {
      throw ConfigurationException(
        'Missing required compile-time environment variable(s): '
        '${missingSupabaseVariables.join(', ')}. Run Flutter with '
        '--dart-define-from-file=config/env.<environment>.local.json.',
      );
    }

    final trimmedPublishableKey = supabasePublishableKey.trim();
    if (_isServerOnlySupabaseKey(trimmedPublishableKey)) {
      throw const ConfigurationException(
        'SUPABASE_PUBLISHABLE_KEY must contain a client-safe publishable key.',
      );
    }

    final parsedSupabaseUrl = _parseHttpUrl(supabaseUrl, name: 'SUPABASE_URL')!;
    final parsedEnableStorefront = _parseStrictBoolean(
      enableStorefront,
      name: 'ENABLE_STOREFRONT',
      defaultValue: false,
    );
    final parsedStorefrontSchemaAvailable = _parseStrictBoolean(
      storefrontSchemaAvailable,
      name: 'STOREFRONT_SCHEMA_AVAILABLE',
      defaultValue: false,
    );

    if (requireExplicitProductionValues && parsedFlavor == AppFlavor.production) {
      if (enableStorefront.trim().isEmpty) {
        throw const ConfigurationException(
          'Production requires an explicit ENABLE_STOREFRONT=true or false value.',
        );
      }
      if (parsedSupabaseUrl.scheme != 'https') {
        throw const ConfigurationException('Production SUPABASE_URL must use HTTPS.');
      }
      final projectRef = productionSupabaseProjectRef.trim().toLowerCase();
      if (projectRef.isEmpty || parsedSupabaseUrl.host != '$projectRef.supabase.co') {
        throw const ConfigurationException(
          'PRODUCTION_SUPABASE_PROJECT_REF must be explicit and match SUPABASE_URL.',
        );
      }
      if (!_isClientSafeSupabaseKey(trimmedPublishableKey)) {
        throw const ConfigurationException(
          'Production SUPABASE_PUBLISHABLE_KEY must be a client-safe Supabase publishable key.',
        );
      }
      if (parsedEnableStorefront && !parsedStorefrontSchemaAvailable) {
        throw const ConfigurationException(
          'ENABLE_STOREFRONT=true requires STOREFRONT_SCHEMA_AVAILABLE=true.',
        );
      }
    }

    return AppEnvironment(
      flavor: parsedFlavor,
      apiBaseUrl: _parseHttpUrl(apiBaseUrl, name: 'apiBaseUrl', allowEmpty: true),
      supabaseUrl: parsedSupabaseUrl,
      supabasePublishableKey: trimmedPublishableKey,
      enableStorefront: parsedEnableStorefront,
    );
  }

  final AppFlavor flavor;
  final Uri? apiBaseUrl;
  final Uri supabaseUrl;
  final String supabasePublishableKey;
  final bool enableStorefront;

  bool get hasApiConfiguration => apiBaseUrl != null;
}

bool _parseStrictBoolean(String value, {required String name, required bool defaultValue}) {
  return switch (value.trim().toLowerCase()) {
    '' => defaultValue,
    'true' => true,
    'false' => false,
    _ => throw ConfigurationException('$name must be either true or false.'),
  };
}

Uri? _parseHttpUrl(String value, {required String name, bool allowEmpty = false}) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty && allowEmpty) {
    return null;
  }

  final parsedUrl = Uri.tryParse(trimmedValue);
  if (parsedUrl == null ||
      !parsedUrl.hasAuthority ||
      (parsedUrl.scheme != 'http' && parsedUrl.scheme != 'https')) {
    throw ArgumentError.value(value, name, 'Expected an absolute HTTP or HTTPS URL');
  }
  return parsedUrl;
}

bool _isServerOnlySupabaseKey(String key) {
  if (key.startsWith('sb_secret_')) {
    return true;
  }

  final segments = key.split('.');
  if (segments.length != 3) {
    return false;
  }

  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
    final claims = jsonDecode(payload);
    return claims is Map<String, dynamic> && claims['role'] == 'service_role';
  } on FormatException {
    return false;
  }
}

bool _isClientSafeSupabaseKey(String key) {
  if (key.startsWith('sb_publishable_') &&
      key.length > 'sb_publishable_'.length &&
      !key.toLowerCase().contains('replace_me')) {
    return true;
  }

  final segments = key.split('.');
  if (segments.length != 3) return false;

  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
    final claims = jsonDecode(payload);
    return claims is Map<String, dynamic> && claims['role'] == 'anon';
  } on FormatException {
    return false;
  }
}
