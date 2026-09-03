import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  throw StateError('authServiceProvider must be overridden at the application root.');
});

final authUserProvider = StreamProvider<AuthenticatedUser?>((ref) async* {
  final service = ref.watch(authServiceProvider);
  var previous = service.currentUser;
  yield previous;
  await for (final user in service.userChanges) {
    if (user?.id == previous?.id) continue;
    previous = user;
    yield user;
  }
}, retry: (retryCount, error) => null);

final authFormControllerProvider = NotifierProvider.autoDispose<AuthFormController, AuthFormState>(
  AuthFormController.new,
);

final signOutControllerProvider = NotifierProvider.autoDispose<SignOutController, SignOutState>(
  SignOutController.new,
);

final class AuthFormState {
  const AuthFormState({this.isSubmitting = false, this.message});

  final bool isSubmitting;
  final String? message;
}

final class AuthFormController extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => const AuthFormState();

  Future<void> submit({
    required String email,
    required String password,
    required bool signUp,
  }) async {
    if (state.isSubmitting) return;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      state = const AuthFormState(message: 'Enter an email and password.');
      return;
    }

    state = const AuthFormState(isSubmitting: true);
    try {
      final service = ref.read(authServiceProvider);
      if (signUp) {
        final result = await service.signUp(email: normalizedEmail, password: password);
        if (!ref.mounted) return;
        state = AuthFormState(
          message: result.requiresEmailConfirmation
              ? 'Check your email to confirm the account, then sign in.'
              : null,
        );
      } else {
        await service.signIn(email: normalizedEmail, password: password);
        if (ref.mounted) state = const AuthFormState();
      }
    } on AuthenticationException catch (error) {
      if (ref.mounted) state = AuthFormState(message: error.message);
    } on Object {
      if (ref.mounted) {
        state = const AuthFormState(message: 'Authentication is unavailable. Please try again.');
      }
    }
  }
}

final class SignOutState {
  const SignOutState({this.isSubmitting = false, this.error});

  final bool isSubmitting;
  final String? error;
}

final class SignOutController extends Notifier<SignOutState> {
  @override
  SignOutState build() => const SignOutState();

  Future<void> signOut() async {
    if (state.isSubmitting) return;
    state = const SignOutState(isSubmitting: true);
    try {
      await ref.read(authServiceProvider).signOut();
      if (ref.mounted) state = const SignOutState();
    } on AuthenticationException catch (error) {
      if (ref.mounted) state = SignOutState(error: error.message);
    } on Object {
      if (ref.mounted) {
        state = const SignOutState(error: 'Sign-out is unavailable. Please try again.');
      }
    }
  }
}
