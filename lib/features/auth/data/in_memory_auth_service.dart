import 'dart:async';

import '../application/auth_service.dart';

final class InMemoryAuthService implements AuthService {
  InMemoryAuthService({AuthenticatedUser? currentUser}) : _currentUser = currentUser;

  AuthenticatedUser? _currentUser;
  final _changes = StreamController<AuthenticatedUser?>.broadcast();

  @override
  AuthenticatedUser? get currentUser => _currentUser;

  @override
  Stream<AuthenticatedUser?> get userChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthenticationException('Enter an email and password.');
    }
    _currentUser = AuthenticatedUser(id: 'user-demo', email: email.trim());
    _changes.add(_currentUser);
  }

  @override
  Future<AuthSignUpResult> signUp({required String email, required String password}) async {
    await signIn(email: email, password: password);
    return const AuthSignUpResult(requiresEmailConfirmation: false);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _changes.add(null);
  }
}
