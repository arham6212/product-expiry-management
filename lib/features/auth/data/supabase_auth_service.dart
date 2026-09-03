import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/auth_service.dart';

final class SupabaseAuthService implements AuthService {
  const SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  AuthenticatedUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AuthenticatedUser?> get userChanges {
    return _client.auth.onAuthStateChange.map((event) => _mapUser(event.session?.user));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (error) {
      throw AuthenticationException(
        'Sign-in failed. Check your email and password, then try again.',
        cause: error,
      );
    }
  }

  @override
  Future<AuthSignUpResult> signUp({required String email, required String password}) async {
    try {
      final response = await _client.auth.signUp(email: email.trim(), password: password);
      return AuthSignUpResult(requiresEmailConfirmation: response.session == null);
    } on AuthException catch (error) {
      throw AuthenticationException(
        'Account creation failed. Check the email and password requirements, then try again.',
        cause: error,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthenticationException('Sign-out failed. Please try again.', cause: error);
    }
  }
}

AuthenticatedUser? _mapUser(User? user) {
  if (user == null) return null;
  return AuthenticatedUser(id: user.id, email: user.email ?? '');
}
