final class AuthenticatedUser {
  const AuthenticatedUser({required this.id, required this.email});

  final String id;
  final String email;
}

final class AuthSignUpResult {
  const AuthSignUpResult({required this.requiresEmailConfirmation});

  final bool requiresEmailConfirmation;
}

final class AuthenticationException implements Exception {
  const AuthenticationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AuthenticationException: $message';
}

abstract interface class AuthService {
  AuthenticatedUser? get currentUser;

  Stream<AuthenticatedUser?> get userChanges;

  Future<void> signIn({required String email, required String password});

  Future<AuthSignUpResult> signUp({required String email, required String password});

  Future<void> signOut();
}
