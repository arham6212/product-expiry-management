sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class ConfigurationException extends AppException {
  const ConfigurationException(super.message, {super.cause});
}

final class InfrastructureException extends AppException {
  const InfrastructureException(super.message, {super.cause});
}
