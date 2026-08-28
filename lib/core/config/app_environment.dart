enum AppFlavor { development, staging, production }

class AppEnvironment {
  const AppEnvironment({required this.flavor, required this.apiBaseUrl});

  factory AppEnvironment.fromCompileTime() {
    const flavor = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
    return AppEnvironment.parse(flavor: flavor, apiBaseUrl: apiBaseUrl);
  }

  factory AppEnvironment.parse({required String flavor, String apiBaseUrl = ''}) {
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

    final trimmedBaseUrl = apiBaseUrl.trim();
    final parsedBaseUrl = trimmedBaseUrl.isEmpty ? null : Uri.tryParse(trimmedBaseUrl);
    if (trimmedBaseUrl.isNotEmpty && parsedBaseUrl == null) {
      throw ArgumentError.value(apiBaseUrl, 'apiBaseUrl', 'Expected a valid URL');
    }
    if (parsedBaseUrl != null &&
        (!parsedBaseUrl.hasAuthority ||
            (parsedBaseUrl.scheme != 'http' && parsedBaseUrl.scheme != 'https'))) {
      throw ArgumentError.value(apiBaseUrl, 'apiBaseUrl', 'Expected an absolute HTTP or HTTPS URL');
    }

    return AppEnvironment(flavor: parsedFlavor, apiBaseUrl: parsedBaseUrl);
  }

  final AppFlavor flavor;
  final Uri? apiBaseUrl;

  bool get hasApiConfiguration => apiBaseUrl != null;
}
