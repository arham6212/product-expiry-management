import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import '../application/auth_controller.dart';
import 'no_shop_page.dart';

typedef AuthenticatedShopBuilder =
    Widget Function(BuildContext context, ShopAccess access, VoidCallback? selectAnotherShop);

class AuthenticatedShopGate extends ConsumerWidget {
  const AuthenticatedShopGate({required this.enableStorefront, this.builder, super.key});

  final bool enableStorefront;
  final AuthenticatedShopBuilder? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authUserProvider);
    return switch (authUser) {
      AsyncLoading() => const _GateMessage(
        key: Key('loadingAuthState'),
        icon: Icons.lock_outline,
        title: 'Loading account…',
        showProgress: true,
      ),
      AsyncError() => _GateMessage(
        key: const Key('authLoadErrorState'),
        icon: Icons.cloud_off_outlined,
        title: 'Account could not be loaded',
        message: 'Check the connection and try again.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(authUserProvider),
      ),
      AsyncData(:final value) when value == null => const _EmailPasswordPage(),
      AsyncData() => _buildAuthenticated(context, ref),
    };
  }

  Widget _buildAuthenticated(BuildContext context, WidgetRef ref) {
    final session = ref.watch(shopSessionControllerProvider);
    return switch (session) {
      AsyncLoading() => const _GateMessage(
        key: Key('loadingShopsState'),
        icon: Icons.store_outlined,
        title: 'Loading your shops…',
        showProgress: true,
      ),
      AsyncError() => _GateMessage(
        key: const Key('shopLoadErrorState'),
        icon: Icons.cloud_off_outlined,
        title: 'Shops could not be loaded',
        message: 'Check the connection and try again.',
        actionLabel: 'Try again',
        onAction: () => ref.read(shopSessionControllerProvider.notifier).retry(),
      ),
      AsyncData(:final value) when value.shops.isEmpty => NoShopPage(session: value),
      AsyncData(:final value) when value.isChoosingShop || value.activeShop == null =>
        _ShopSelectionPage(shops: value.shops),
      AsyncData(:final value) => _buildActiveShop(context, ref, value),
    };
  }

  Widget _buildActiveShop(BuildContext context, WidgetRef ref, ShopSessionState session) {
    final activeShop = session.activeShop!;
    final selectAnother = session.shops.length > 1
        ? () => ref.read(shopSessionControllerProvider.notifier).chooseAnotherShop()
        : null;
    return builder?.call(context, activeShop, selectAnother) ??
        AppShell(enableStorefront: enableStorefront);
  }
}

class _EmailPasswordPage extends ConsumerStatefulWidget {
  const _EmailPasswordPage();

  @override
  ConsumerState<_EmailPasswordPage> createState() => _EmailPasswordPageState();
}

class _EmailPasswordPageState extends ConsumerState<_EmailPasswordPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authFormControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'Sign in for shop operations',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Sign in to check expiries and receive stock.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('authEmailField'),
                    controller: _emailController,
                    enabled: !state.isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('authPasswordField'),
                    controller: _passwordController,
                    enabled: !state.isSubmitting,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(signUp: false),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (state.message != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        state.message!,
                        key: const Key('authMessage'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('signInButton'),
                    onPressed: state.isSubmitting ? null : () => _submit(signUp: false),
                    child: state.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  TextButton(
                    key: const Key('signUpButton'),
                    onPressed: state.isSubmitting ? null : () => _submit(signUp: true),
                    child: const Text('Create account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit({required bool signUp}) {
    return ref
        .read(authFormControllerProvider.notifier)
        .submit(email: _emailController.text, password: _passwordController.text, signUp: signUp);
  }
}

class _ShopSelectionPage extends ConsumerWidget {
  const _ShopSelectionPage({required this.shops});

  final List<ShopAccess> shops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select shop')),
      body: ListView(
        key: const Key('shopSelectionList'),
        padding: const EdgeInsets.all(20),
        children: [
          for (final access in shops)
            Card(
              child: ListTile(
                title: Text(access.shop.name),
                subtitle: Text(access.membership.role.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref.read(shopSessionControllerProvider.notifier).selectShop(access),
              ),
            ),
        ],
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.showProgress = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppStatePanel(
            icon: icon,
            title: title,
            message: message ?? 'Please wait a moment.',
            actionLabel: actionLabel,
            onAction: onAction,
            showProgress: showProgress,
          ),
        ),
      ),
    );
  }
}
