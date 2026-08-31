import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';

class StaffNotification {
  final String id;
  final String title;
  final String body;
  final String? url;
  final DateTime createdAt;
  final DateTime? readAt;

  StaffNotification.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      body = json['body'] as String,
      url = json['url'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String),
      readAt = json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null;
}

final staffNotificationsProvider =
    FutureProvider.autoDispose<List<StaffNotification>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final user = client.auth.currentUser;
      if (user == null) return [];

      final rows = await client
          .from('staff_notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      return (rows as List)
          .map((r) => StaffNotification.fromJson(r as Map<String, dynamic>))
          .toList();
    });

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final notifications = await ref.watch(staffNotificationsProvider.future);
  return notifications.where((n) => n.readAt == null).length;
});

void _openNotification(
  BuildContext context,
  WidgetRef ref,
  StaffNotification n,
) {
  if (n.readAt == null) {
    ref
        .read(supabaseProvider)
        .from('staff_notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('id', n.id)
        .then((_) {
          if (context.mounted) ref.invalidate(staffNotificationsProvider);
        });
  }

  final url = n.url;
  if (url == null || url.isEmpty) return;
  if (url.startsWith('/')) {
    // go(), not push(): several deep-link targets (e.g. /staff/members,
    // /staff/billing) are StatefulShellRoute branches — pushing them from
    // inside an already-pushed screen mounts them in the wrong nested
    // navigator and renders blank. go() re-resolves the full route tree
    // (including the shell + correct branch), which always works.
    context.go(url);
  } else {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(staffNotificationsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(
        child: notifications.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load: $e')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text(
                  'No notifications yet',
                  style: TextStyle(color: AppTheme.inkSoft),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(staffNotificationsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NotificationTile(
                  notification: items[i],
                  onTap: () => _openNotification(context, ref, items[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final StaffNotification notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final unread = notification.readAt == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread
                ? AppTheme.accent.withValues(alpha: 0.25)
                : AppTheme.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unread)
              Container(
                margin: const EdgeInsets.only(top: 6, right: 10),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.statusDanger,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _relativeTime(notification.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
