import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shops/application/shop_session_controller.dart';
import '../../shops/presentation/scan_qr_screen.dart';

typedef InviteCodeScanner = Future<String?> Function(BuildContext context);

class NoShopPage extends ConsumerStatefulWidget {
  const NoShopPage({required this.session, this.scanInviteCode, super.key});

  final ShopSessionState session;
  final InviteCodeScanner? scanInviteCode;

  @override
  ConsumerState<NoShopPage> createState() => _NoShopPageState();
}

class _NoShopPageState extends ConsumerState<NoShopPage> {
  final _createController = TextEditingController();
  final _joinController = TextEditingController();

  @override
  void dispose() {
    _createController.dispose();
    _joinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    if (session.pendingRequest != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_empty, size: 56),
                  const SizedBox(height: 16),
                  Text('Join Request Pending', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Waiting for shop owner to approve your request.'),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => ref.read(shopSessionControllerProvider.notifier).retry(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check Status'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Create a new shop', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('createShopNameField'),
                    controller: _createController,
                    enabled: !session.isCreatingShop && !session.isJoiningShop,
                    decoration: const InputDecoration(labelText: 'Shop name'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('createShopButton'),
                    onPressed: (session.isCreatingShop || session.isJoiningShop)
                        ? null
                        : () => ref
                              .read(shopSessionControllerProvider.notifier)
                              .createFirstShop(_createController.text),
                    child: session.isCreatingShop
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create shop'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('OR', style: TextStyle(color: Colors.grey)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  Text('Join an existing shop', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('joinShopCodeField'),
                          controller: _joinController,
                          enabled: !session.isCreatingShop && !session.isJoiningShop,
                          decoration: const InputDecoration(labelText: '6-character invite code'),
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => ref
                              .read(shopSessionControllerProvider.notifier)
                              .clearScannedInviteCode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'Scan QR Code',
                        onPressed: (session.isCreatingShop || session.isJoiningShop)
                            ? null
                            : () async {
                                final code = await (widget.scanInviteCode ?? _openInviteScanner)(
                                  context,
                                );
                                if (!mounted) return;
                                if (code != null) {
                                  _joinController.text = code;
                                  ref
                                      .read(shopSessionControllerProvider.notifier)
                                      .selectScannedInviteCode(code);
                                }
                              },
                      ),
                    ],
                  ),
                  if (session.scannedInviteCode != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      key: const Key('scannedInviteConfirmation'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_2),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Scanned invite ${session.scannedInviteCode}. '
                                'Review it, then confirm below.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (session.actionError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      session.actionError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const Key('joinShopButton'),
                    onPressed: (session.isCreatingShop || session.isJoiningShop)
                        ? null
                        : () => ref
                              .read(shopSessionControllerProvider.notifier)
                              .requestToJoinShop(_joinController.text),
                    child: session.isJoiningShop
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Request to join'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _openInviteScanner(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute<String>(builder: (_) => const ScanQrScreen()));
}
