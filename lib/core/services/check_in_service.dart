import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'activity_log_service.dart';
import 'app_events.dart';
import 'data_refresh.dart';
import 'offline_checkin_queue.dart';
import 'review_prompt.dart';

/// Outcome of one check-in attempt.
class CheckInOutcome {
  final bool success;

  /// The member was already checked in today — not an error, just a no-op.
  final bool already;
  final String title;
  final String? subtitle;
  final String? avatarUrl;

  const CheckInOutcome({
    required this.success,
    this.already = false,
    required this.title,
    this.subtitle,
    this.avatarUrl,
  });
}

/// The single online check-in path: validates the member belongs to this gym
/// and is active, inserts the row (the unique index blocks a second check-in
/// on the same day), and logs the activity.
///
/// Offline queueing is the caller's business — only the check-in screen's QR
/// scanner can queue, because a queued row has no name to show back.
Future<CheckInOutcome> checkInMember({
  required String memberId,
  required String gymId,
  String method = 'manual',
}) async {
  final client = Supabase.instance.client;
  try {
    // Cache gym_id after every successful network fetch so offline mode works.
    await OfflineCheckInQueue.cacheGymId(gymId);

    final member = await client
        .from('members')
        .select('id, first_name, last_name, status, avatar_url')
        .eq('id', memberId)
        .eq('gym_id', gymId)
        .maybeSingle();

    if (member == null) {
      return const CheckInOutcome(
        success: false,
        title: 'Member not found',
        subtitle: 'This QR code is not a member of your gym.',
      );
    }

    final name = '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'
        .trim();
    final label = name.isNotEmpty ? name : 'Member';
    final avatarUrl = member['avatar_url'] as String?;

    if ((member['status'] as String) != 'active') {
      unawaited(
        client.rpc(
          'notify_owner_expired_checkin',
          params: {
            'p_gym_id': gymId,
            'p_member_name': label,
            'p_member_status': member['status'],
            'p_method': method,
          },
        ),
      );
      return CheckInOutcome(
        success: false,
        title: label,
        subtitle: 'Not active (${member['status']}). Check-in blocked.',
        avatarUrl: avatarUrl,
      );
    }

    try {
      await client.from('check_ins').insert({
        'member_id': memberId,
        'gym_id': gymId,
        'method': method,
        'staff_id': client.auth.currentUser?.id,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return CheckInOutcome(
          success: false,
          already: true,
          title: label,
          subtitle: 'Already checked in. Check them out first.',
          avatarUrl: avatarUrl,
        );
      }
      rethrow;
    }

    ActivityLogService.logActivity(
      gymId: gymId,
      action: 'check_in',
      metadata: {'member_id': memberId, 'member_name': label, 'method': method},
    );
    unawaited(ReviewPrompt.recordSuccess());
    unawaited(AppEvents.checkinCompleted());
    notifyGymDataChanged();

    return CheckInOutcome(
      success: true,
      title: label,
      subtitle: 'Checked in successfully.',
      avatarUrl: avatarUrl,
    );
  } catch (e) {
    return CheckInOutcome(success: false, title: 'Error', subtitle: '$e');
  }
}
