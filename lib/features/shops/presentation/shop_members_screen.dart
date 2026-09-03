import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/shop_invite_qr.dart';
import '../application/shop_members_controller.dart';
import '../application/shop_session_controller.dart';

class ShopMembersScreen extends ConsumerWidget {
  const ShopMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shopMembersControllerProvider);
    final session = ref.watch(shopSessionControllerProvider).value;
    final isOwner = session?.activeShop?.membership.role == ShopMembershipRole.owner;

    return Scaffold(
      appBar: AppBar(title: const Text('Team & Access')),
      body: state.when(
        data: (data) => _buildContent(context, ref, data, isOwner),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load team data.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(shopMembersControllerProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, ShopMembersState state, bool isOwner) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (state.actionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              state.actionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),

        if (isOwner) _buildInviteSection(context, ref, state),
        if (isOwner) const Divider(),

        if (isOwner && state.pendingRequests.isNotEmpty) ...[
          _buildPendingRequests(context, ref, state),
          const Divider(),
        ],

        _buildMembersList(context, state.members, isOwner),
      ],
    );
  }

  Widget _buildInviteSection(BuildContext context, WidgetRef ref, ShopMembersState state) {
    final activeInvite = state.activeInvite;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite Code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Share this code with workers so they can request to join.'),
          const SizedBox(height: 16),
          if (activeInvite != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    key: ValueKey(ShopInviteQr.encode(activeInvite.code)),
                    data: ShopInviteQr.encode(activeInvite.code),
                    version: QrVersions.auto,
                    size: 120,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          activeInvite.code,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expires ${_formatDate(activeInvite.expiresAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: activeInvite.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                          Builder(
                            builder: (buttonContext) => TextButton.icon(
                              onPressed: () => _shareInvite(buttonContext, activeInvite.code),
                              icon: const Icon(Icons.share),
                              label: const Text('Share code'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: state.isProcessingAction
                            ? null
                            : () {
                                ref.read(shopMembersControllerProvider.notifier).rotateInvite();
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Generate New Code'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const Text(
              'Joining is currently disabled.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),

          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              Switch(
                value: activeInvite != null,
                onChanged: state.isProcessingAction
                    ? null
                    : (value) {
                        ref.read(shopMembersControllerProvider.notifier).toggleInviteStatus(value);
                      },
              ),
              const Text('Allow joining'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequests(BuildContext context, WidgetRef ref, ShopMembersState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Pending Requests', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (state.pendingRequests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No pending requests.'),
          )
        else
          for (final req in state.pendingRequests)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(req.email),
              subtitle: Text('Requested ${req.createdAt.toLocal().toString().split('.')[0]}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: state.isProcessingAction
                        ? null
                        : () {
                            ref
                                .read(shopMembersControllerProvider.notifier)
                                .reviewRequest(req.requestId, JoinRequestStatus.approved);
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: state.isProcessingAction
                        ? null
                        : () {
                            ref
                                .read(shopMembersControllerProvider.notifier)
                                .reviewRequest(req.requestId, JoinRequestStatus.rejected);
                          },
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildMembersList(BuildContext context, List<ShopMemberProfile> members, bool isOwner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            isOwner ? 'Team Members' : 'My Membership',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No members found.'),
          )
        else
          for (final member in members)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(member.email),
              subtitle: Text('Joined ${member.createdAt.toLocal().toString().split(' ')[0]}'),
              trailing: Chip(label: Text(member.role.name)),
            ),
      ],
    );
  }
}

String _formatDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Future<void> _shareInvite(BuildContext context, String code) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: 'Join my shop with invite code $code.',
      sharePositionOrigin: renderBox == null
          ? null
          : renderBox.localToGlobal(Offset.zero) & renderBox.size,
    ),
  );
}
