import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _memberCheckInsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return [];

  final member = await client.from('members').select('id').eq('user_id', user.id).maybeSingle();
  if (member == null) return [];

  final memberId = member['id'] as String;

  return await client
      .from('check_ins')
      .select('id, checked_in_at')
      .eq('member_id', memberId)
      .order('checked_in_at', ascending: false)
      .limit(10);
});

final _memberMonthCheckInsCountProvider = FutureProvider<int>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return 0;

  final member = await client.from('members').select('id').eq('user_id', user.id).maybeSingle();
  if (member == null) return 0;

  final memberId = member['id'] as String;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);

  final result = await client
      .from('check_ins')
      .select('id')
      .eq('member_id', memberId)
      .gte('checked_in_at', startOfMonth.toIso8601String())
      .count(CountOption.exact);

  return result.count ?? 0;
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class PortalHomeScreen extends ConsumerWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(memberRecordProvider);
    final recentCheckins = ref.watch(_memberCheckInsProvider);
    final monthVisits = ref.watch(_memberMonthCheckInsCountProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Gym'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_outlined),
            onPressed: () => context.push('/portal/qr'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Sign out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(authNotifierProvider.notifier).signOut();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.ink,
        onRefresh: () async {
          ref.invalidate(memberRecordProvider);
          ref.invalidate(_memberCheckInsProvider);
          ref.invalidate(_memberMonthCheckInsCountProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: member.when(
            loading: () => const _LoadingSkeleton(),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error loading profile', style: const TextStyle(color: AppTheme.inkHint, fontSize: 14)),
              ),
            ),
            data: (m) {
              if (m == null) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Profile not found', style: TextStyle(color: AppTheme.inkHint)),
                  ),
                );
              }

              final firstName = m['first_name'] as String? ?? 'Member';
              final lastName = m['last_name'] as String? ?? '';
              final status = m['status'] as String? ?? 'active';
              final memberships = (m['memberships'] as List?) ?? [];
              final currentMs = memberships.isNotEmpty ? memberships.first as Map<String, dynamic> : null;
              final plan = currentMs?['membership_plans'] as Map<String, dynamic>?;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GreetingHeader(firstName: firstName, status: status),
                  const SizedBox(height: 16),
                  _MembershipStatusCard(membership: currentMs, plan: plan),
                  const SizedBox(height: 16),
                  _QuickStatsRow(
                    monthVisitsAsync: monthVisits,
                    recentCheckinsAsync: recentCheckins,
                  ),
                  const SizedBox(height: 16),
                  _QuickLinksGrid(),
                  const SizedBox(height: 16),
                  _RecentCheckInsCard(recentCheckinsAsync: recentCheckins),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Loading Skeleton ─────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (i) => Container(
        height: i == 0 ? 80 : 100,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(12)),
      )),
    );
  }
}

// ─── Greeting Header ──────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String firstName;
  final String status;

  const _GreetingHeader({required this.firstName, required this.status});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    Color statusBg;
    Color statusFg;
    switch (status.toLowerCase()) {
      case 'active':
        statusBg = AppTheme.statusActiveBg;
        statusFg = AppTheme.statusActive;
        break;
      case 'expired':
        statusBg = AppTheme.statusDangerBg;
        statusFg = AppTheme.statusDanger;
        break;
      default:
        statusBg = AppTheme.statusNeutralBg;
        statusFg = AppTheme.statusNeutral;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting,',
                  style: const TextStyle(fontSize: 13, color: AppTheme.inkHint, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  firstName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
            child: Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusFg),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Membership Status Card ───────────────────────────────────────────────────

class _MembershipStatusCard extends StatelessWidget {
  final Map<String, dynamic>? membership;
  final Map<String, dynamic>? plan;

  const _MembershipStatusCard({required this.membership, required this.plan});

  @override
  Widget build(BuildContext context) {
    if (membership == null) {
      return Container(
        decoration: AppTheme.cardDecoration(),
        padding: const EdgeInsets.all(20),
        child: const Center(
          child: Text('No active membership', style: TextStyle(fontSize: 14, color: AppTheme.inkHint)),
        ),
      );
    }

    final status = membership!['status'] as String? ?? 'active';
    final startsAt = membership!['starts_at'] as String?;
    final endsAt = membership!['ends_at'] as String?;
    final planName = plan?['name'] as String? ?? 'Membership';
    final price = plan?['price'];
    final billingInterval = plan?['billing_interval'] as String?;

    Color statusBg;
    Color statusFg;
    switch (status.toLowerCase()) {
      case 'active':
        statusBg = AppTheme.statusActiveBg;
        statusFg = AppTheme.statusActive;
        break;
      case 'expired':
        statusBg = AppTheme.statusDangerBg;
        statusFg = AppTheme.statusDanger;
        break;
      default:
        statusBg = AppTheme.statusNeutralBg;
        statusFg = AppTheme.statusNeutral;
    }

    // Days remaining
    int? daysLeft;
    if (endsAt != null) {
      try {
        final expiry = DateTime.parse(endsAt);
        daysLeft = expiry.difference(DateTime.now()).inDays;
      } catch (e) {
        debugPrint('[GymCRM] Parse expiry date error: $e');
      }
    }

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Text('Your Membership', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusFg),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(planName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                    if (price != null && billingInterval != null)
                      Text(
                        '${formatCurrency(price is num ? price : num.tryParse(price.toString()) ?? 0)} / $billingInterval',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (startsAt != null)
                      Expanded(
                        child: _MsDetailCell(label: 'Started', value: formatDateFromString(startsAt)),
                      ),
                    if (endsAt != null)
                      Expanded(
                        child: _MsDetailCell(label: 'Expires', value: formatDateFromString(endsAt)),
                      ),
                    if (daysLeft != null)
                      Expanded(
                        child: _MsDetailCell(
                          label: 'Days left',
                          value: daysLeft > 0 ? '$daysLeft' : 'Expired',
                          valueColor: daysLeft <= 7 ? AppTheme.statusDanger : daysLeft <= 14 ? AppTheme.statusWarn : AppTheme.statusActive,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MsDetailCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MsDetailCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.inkHint, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor ?? AppTheme.ink),
        ),
      ],
    );
  }
}

// ─── Quick Stats Row ──────────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  final AsyncValue<int> monthVisitsAsync;
  final AsyncValue<List<Map<String, dynamic>>> recentCheckinsAsync;

  const _QuickStatsRow({required this.monthVisitsAsync, required this.recentCheckinsAsync});

  int _calcStreak(List<Map<String, dynamic>> checkins) {
    if (checkins.isEmpty) return 0;
    final sorted = [...checkins]..sort((a, b) {
        final da = DateTime.tryParse(a['checked_in_at'] as String? ?? '') ?? DateTime(1970);
        final db = DateTime.tryParse(b['checked_in_at'] as String? ?? '') ?? DateTime(1970);
        return db.compareTo(da);
      });

    int streak = 0;
    DateTime? lastDay;
    for (final ci in sorted) {
      final dt = DateTime.tryParse(ci['checked_in_at'] as String? ?? '');
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (lastDay == null) {
        streak = 1;
        lastDay = day;
      } else if (lastDay.difference(day).inDays == 1) {
        streak++;
        lastDay = day;
      } else {
        break;
      }
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final monthVisits = monthVisitsAsync.maybeWhen(data: (v) => v, orElse: () => 0);
    final streak = recentCheckinsAsync.maybeWhen(
      data: (list) => _calcStreak(list),
      orElse: () => 0,
    );

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle),
                  child: const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.inkSoft),
                ),
                const SizedBox(height: 10),
                Text('$monthVisits', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF8a6800))),
                const SizedBox(height: 2),
                const Text('This month', style: TextStyle(fontSize: 12, color: AppTheme.inkHint, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFFFF3E0), shape: BoxShape.circle),
                  child: const Icon(Icons.local_fire_department_outlined, size: 18, color: AppTheme.statusWarn),
                ),
                const SizedBox(height: 10),
                Text('$streak', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF8a6800))),
                const SizedBox(height: 2),
                const Text('Day streak', style: TextStyle(fontSize: 12, color: AppTheme.inkHint, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Quick Links Grid ─────────────────────────────────────────────────────────

class _QuickLinksGrid extends StatelessWidget {
  const _QuickLinksGrid();

  @override
  Widget build(BuildContext context) {
    final links = [
      _Link('Billing', Icons.receipt_outlined, '/portal/billing', false),
      _Link('Bookings', Icons.calendar_today_outlined, '/portal/bookings', false),
      _Link('My QR', Icons.qr_code_outlined, '/portal/qr', true),
      _Link('Workout', Icons.fitness_center_outlined, '/portal/workout', false),
      _Link('Attendance', Icons.trending_up, '/portal/heatmap', false),
    ];

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Quick Access', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: links.map((l) => _LinkTile(link: l)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Link {
  final String label;
  final IconData icon;
  final String route;
  final bool highlight;
  const _Link(this.label, this.icon, this.route, this.highlight);
}

class _LinkTile extends StatelessWidget {
  final _Link link;
  const _LinkTile({required this.link});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(link.route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: link.highlight ? AppTheme.accent.withValues(alpha: 0.12) : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: link.highlight ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: link.highlight ? AppTheme.accent : AppTheme.activeBg,
                shape: BoxShape.circle,
              ),
              child: Icon(link.icon, size: 16, color: link.highlight ? AppTheme.accentFg : AppTheme.inkSoft),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(link.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recent Check-ins Card ────────────────────────────────────────────────────

class _RecentCheckInsCard extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> recentCheckinsAsync;
  const _RecentCheckInsCard({required this.recentCheckinsAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent Check-ins', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          recentCheckinsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink)),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Failed to load check-ins', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
            ),
            data: (checkins) {
              if (checkins.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No check-ins yet', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: checkins.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                itemBuilder: (_, i) {
                  final ci = checkins[i];
                  final checkedInAt = ci['checked_in_at'] as String?;
                  String dateStr = '';
                  String timeStr = '';
                  if (checkedInAt != null) {
                    try {
                      final dt = DateTime.parse(checkedInAt).toLocal();
                      dateStr = formatDateFromString(checkedInAt);
                      final h = dt.hour;
                      final m = dt.minute.toString().padLeft(2, '0');
                      final period = h >= 12 ? 'PM' : 'AM';
                      final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
                      timeStr = '$displayH:$m $period';
                    } catch (e) {
                      debugPrint('[GymCRM] Parse check-in time error: $e');
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.statusActiveBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.fitness_center_outlined, size: 18, color: AppTheme.statusActive),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Gym Visit', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                              if (dateStr.isNotEmpty)
                                Text(dateStr, style: const TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(20)),
                          child: Text(timeStr.isNotEmpty ? timeStr : 'In', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.statusActive)),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
