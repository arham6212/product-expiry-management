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
    const flavor = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const enableStorefront = String.fromEnvironment('ENABLE_STOREFRONT');
    return AppEnvironment.parse(
      flavor: flavor,
      apiBaseUrl: apiBaseUrl,
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      enableStorefront: enableStorefront,
    );
  }

  factory AppEnvironment.parse({
    required String flavor,
    String apiBaseUrl = '',
    String supabaseUrl = '',
    String supabasePublishableKey = '',
    String enableStorefront = '',
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
        '--dart-define-from-file=config/env.local.json.',
      );
    }

    final trimmedPublishableKey = supabasePublishableKey.trim();
    if (_isServerOnlySupabaseKey(trimmedPublishableKey)) {
      throw const ConfigurationException(
        'SUPABASE_PUBLISHABLE_KEY must contain a client-safe publishable key.',
      );
    }

    return AppEnvironment(
      flavor: parsedFlavor,
      apiBaseUrl: _parseHttpUrl(apiBaseUrl, name: 'apiBaseUrl', allowEmpty: true),
      supabaseUrl: _parseHttpUrl(supabaseUrl, name: 'SUPABASE_URL')!,
      supabasePublishableKey: trimmedPublishableKey,
      enableStorefront: _parseStrictBoolean(
        enableStorefront,
        name: 'ENABLE_STOREFRONT',
        defaultValue: false,
      ),
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
