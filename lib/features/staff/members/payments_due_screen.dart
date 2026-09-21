import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/access/role_access.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/data_refresh.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import 'upcoming_payments_screen.dart' show QuickCollectSheet;

// ── Payments due ─────────────────────────────────────────────────────────────
// Everyone who owes money or is about to, on one timeline: overdue first, then
// today, then each coming day. A filter row narrows it to overdue / today /
// coming, and a day strip jumps to a single date. Collect sits on the same
// line as the member's name.

enum _Filter { all, overdue, today, coming }

// Overdue can run to dozens of people; on "All" it stops here so it can't
// bury today's and tomorrow's payments.
const _collapsedOverdue = 5;

// How far ahead the "coming" list reaches, and how many of those days get
// their own header + day-strip cell (the rest are grouped as "Later").
const _lookAheadDays = 30;
const _stripDays = 7;

String _ymd(DateTime d) => d.toIso8601String().split('T').first;

String _memberName(Map<String, dynamic> m) {
  final first = m['first_name'] as String? ?? '';
  final last = m['last_name'] as String? ?? '';
  return '$first $last'.trim();
}

class _DueItem {
  final Map<String, dynamic> member;
  final DateTime due; // date only
  final int days; // due date minus today; negative = overdue
  final double? amount; // null when the member has no plan and no invoice
  final String? planName;

  const _DueItem({
    required this.member,
    required this.due,
    required this.days,
    required this.amount,
    required this.planName,
  });

  String get id => member['id'] as String;
  String get name => _memberName(member);
  bool get isHold => (member['status'] as String?) == 'frozen';
}

// One query for members due within the window plus one for their unpaid
// invoices. The amount is the unpaid invoice balance when there is one,
// otherwise the plan price minus the member's discount.
final _dueItemsProvider = FutureProvider.family<List<_DueItem>, String>((
  ref,
  gymId,
) async {
  ref.watch(gymDataVersionProvider); // refetch after a collect elsewhere
  final client = Supabase.instance.client;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final results = await Future.wait([
    client
        .from('members')
        .select(
          'id, first_name, last_name, avatar_url, next_payment_date, status, phone, '
          'memberships(status, discount_amount, billing_interval_days, membership_plans(price, name))',
        )
        .eq('gym_id', gymId)
        .lte(
          'next_payment_date',
          _ymd(today.add(const Duration(days: _lookAheadDays))),
        )
        .not('status', 'eq', 'cancelled')
        .order('next_payment_date', ascending: true),
    client
        .from('invoices')
        .select('member_id, amount, payments(amount, status)')
        .eq('gym_id', gymId)
        .inFilter('status', ['open', 'partial']),
  ]);

  final owed = <String, double>{};
  for (final inv in (results[1] as List).cast<Map<String, dynamic>>()) {
    final paid = ((inv['payments'] as List?) ?? const [])
        .where((p) => (p as Map)['status'] == 'succeeded')
        .fold<double>(
          0,
          (s, p) => s + ((p as Map)['amount'] as num).toDouble(),
        );
    final left = ((inv['amount'] as num?)?.toDouble() ?? 0) - paid;
    final memberId = inv['member_id'] as String?;
    if (memberId != null && left > 0) {
      owed[memberId] = (owed[memberId] ?? 0) + left;
    }
  }

  final items = <_DueItem>[];
  for (final m in (results[0] as List).cast<Map<String, dynamic>>()) {
    final due = DateTime.tryParse(
      ((m['next_payment_date'] as String?) ?? '').split('T').first,
    );
    if (due == null) continue;

    Map<String, dynamic>? active;
    for (final ms in (m['memberships'] as List?) ?? const []) {
      if ((ms as Map)['status'] == 'active') {
        active = ms.cast<String, dynamic>();
        break;
      }
    }
    final plan = active?['membership_plans'] as Map?;
    final balance = owed[m['id']] ?? 0;

    // A day pass ends instead of renewing, so it only belongs here while it
    // still has an unpaid invoice.
    if (active?['billing_interval_days'] != null && balance <= 0) continue;

    double? amount;
    if (balance > 0) {
      amount = balance;
    } else if (plan?['price'] != null) {
      final discount = (active?['discount_amount'] as num?)?.toDouble() ?? 0;
      final net = (plan!['price'] as num).toDouble() - discount;
      amount = net < 0 ? 0 : net;
    }

    items.add(
      _DueItem(
        member: m,
        due: due,
        days: due.difference(today).inDays,
        amount: amount,
        planName: plan?['name'] as String?,
      ),
    );
  }
  return items;
});

class PaymentsDueScreen extends ConsumerStatefulWidget {
  /// Opened from the dashboard's "due in 7 days" tile.
  final bool initialComing;
  const PaymentsDueScreen({super.key, this.initialComing = false});

  @override
  ConsumerState<PaymentsDueScreen> createState() => _PaymentsDueScreenState();
}

class _PaymentsDueScreenState extends ConsumerState<PaymentsDueScreen> {
  late _Filter _filter = widget.initialComing ? _Filter.coming : _Filter.all;
  DateTime? _day; // a single date picked on the strip
  bool _showAllOverdue = false;

  void _setFilter(_Filter f) => setState(() {
    _filter = f;
    _day = null;
    _showAllOverdue = false;
  });

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(gymIdProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Payments Due'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(
        child: gymAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ErrorState(what: 'payments due'),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(String gymId) {
    final async = ref.watch(_dueItemsProvider(gymId));
    final canCollect = RoleAccess.canRecordPayment(
      ref.watch(staffRoleProvider).valueOrNull,
    );
    return async.when(
      // Keep the list on screen while it quietly refetches (after a collect,
      // a check-in flush or coming back to the app).
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'payments due'),
      data: (items) => RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async {
          ref.invalidate(_dueItemsProvider(gymId));
          await ref.read(_dueItemsProvider(gymId).future);
        },
        child: _list(gymId, items, canCollect),
      ),
    );
  }

  Widget _list(String gymId, List<_DueItem> items, bool canCollect) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = items.where((i) => i.days < 0).toList();
    final dueToday = items.where((i) => i.days == 0).toList();
    final coming = items.where((i) => i.days > 0).toList();

    void refresh() => ref.invalidate(_dueItemsProvider(gymId));

    Widget group(
      String title,
      List<_DueItem> list, {
      required _Tone tone,
      int? cap,
      VoidCallback? onShowAll,
    }) => _DueGroup(
      title: title,
      items: list,
      tone: tone,
      canCollect: canCollect,
      cap: cap,
      onShowAll: onShowAll,
      onCollected: refresh,
    );

    final parts = <Widget>[];
    if (items.isEmpty) {
      parts.add(
        const _EmptyNote(
          icon: AppIcons.checkCircle,
          title: 'All caught up',
          sub: 'No overdue or upcoming payments right now.',
        ),
      );
    } else if (_day != null) {
      final day = _day!;
      final list = items.where((i) => i.due == day).toList();
      parts.add(_DayFilterBar(onClear: () => setState(() => _day = null)));
      parts.add(
        list.isEmpty
            ? const _EmptyNote(
                icon: AppIcons.checkCircle,
                title: 'Nothing due that day',
                sub: 'Pick another day or clear the filter.',
              )
            : group(
                _dayHeading(day, today),
                list,
                tone: day == today ? _Tone.today : _Tone.coming,
              ),
      );
    } else {
      switch (_filter) {
        case _Filter.all:
          if (overdue.isNotEmpty) {
            parts.add(
              group(
                'OVERDUE',
                overdue,
                tone: _Tone.overdue,
                cap: _showAllOverdue ? null : _collapsedOverdue,
                onShowAll: () => setState(() => _showAllOverdue = true),
              ),
            );
          }
          if (dueToday.isNotEmpty) {
            parts.add(
              group(
                _dayHeading(today, today),
                dueToday,
                tone: _Tone.today,
              ),
            );
          }
          parts.addAll(_comingGroups(coming, today, group));
        case _Filter.overdue:
          if (overdue.isEmpty) {
            parts.add(
              const _EmptyNote(
                icon: AppIcons.checkCircle,
                title: 'No overdue payments',
                sub: 'Everyone is up to date.',
              ),
            );
          } else {
            parts.add(_OverdueBanner(items: overdue));
            parts.add(const SizedBox(height: 14));
            parts.add(group('OLDEST FIRST', overdue, tone: _Tone.overdue));
          }
        case _Filter.today:
          parts.add(
            dueToday.isEmpty
                ? const _EmptyNote(
                    icon: AppIcons.checkCircle,
                    title: 'Nothing due today',
                    sub: 'Check what is coming up next.',
                  )
                : group(_dayHeading(today, today), dueToday, tone: _Tone.today),
          );
        case _Filter.coming:
          parts.addAll(
            coming.isEmpty
                ? const [
                    _EmptyNote(
                      icon: AppIcons.checkCircle,
                      title: 'Nothing coming up',
                      sub: 'No payments due in the next 30 days.',
                    ),
                  ]
                : _comingGroups(coming, today, group),
          );
      }
    }

    // The strip only makes sense where future days are listed.
    final showStrip =
        items.isNotEmpty &&
        (_filter == _Filter.all || _filter == _Filter.coming);
    final counts = <DateTime, int>{};
    for (final i in items) {
      if (i.days >= 0 && i.days < _stripDays) {
        counts[i.due] = (counts[i.due] ?? 0) + 1;
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FilterRow(
                  selected: _filter,
                  counts: {
                    _Filter.all: items.length,
                    _Filter.overdue: overdue.length,
                    _Filter.today: dueToday.length,
                    _Filter.coming: coming.length,
                  },
                  onSelect: _setFilter,
                ),
                if (showStrip) ...[
                  const SizedBox(height: 12),
                  _DayStrip(
                    today: today,
                    counts: counts,
                    selected: _day,
                    onTap: (d) => setState(() {
                      _day = _day == d ? null : d;
                      _showAllOverdue = false;
                    }),
                  ),
                ],
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Column(
                    key: ValueKey('$_filter-$_day-$_showAllOverdue'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: parts,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // The next few days each get their own header; anything further out is
  // gathered under "Later" so a 30-day window doesn't become 30 headers.
  List<Widget> _comingGroups(
    List<_DueItem> coming,
    DateTime today,
    Widget Function(
      String, List<_DueItem>, {
      required _Tone tone,
      int? cap,
      VoidCallback? onShowAll,
    })
    group,
  ) {
    final byDay = <DateTime, List<_DueItem>>{};
    final later = <_DueItem>[];
    for (final i in coming) {
      if (i.days < _stripDays) {
        byDay.putIfAbsent(i.due, () => []).add(i);
      } else {
        later.add(i);
      }
    }
    return [
      for (final e in byDay.entries)
        group(_dayHeading(e.key, today), e.value, tone: _Tone.coming),
      if (later.isNotEmpty) group('LATER', later, tone: _Tone.coming),
    ];
  }
}

String _dayHeading(DateTime d, DateTime today) {
  final diff = d.difference(today).inDays;
  final date = DateFormat('EEE d MMM').format(d).toUpperCase();
  if (diff == 0) return 'TODAY · $date';
  if (diff == 1) return 'TOMORROW · $date';
  return date;
}

// ── Filter row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final _Filter selected;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onSelect;
  const _FilterRow({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Filter.all: 'All',
      _Filter.overdue: 'Overdue',
      _Filter.today: 'Today',
      _Filter.coming: 'Coming',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _Filter.values) ...[
            _FilterChip(
              label: labels[f]!,
              count: counts[f] ?? 0,
              dot: f == _Filter.overdue && (counts[f] ?? 0) > 0,
              selected: selected == f,
              onTap: () => onSelect(f),
            ),
            if (f != _Filter.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool dot;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.count,
    required this.dot,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.ink : AppTheme.surface,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppTheme.statusDanger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppTheme.numberStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white70 : AppTheme.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Day strip ────────────────────────────────────────────────────────────────

class _DayStrip extends StatelessWidget {
  final DateTime today;
  final Map<DateTime, int> counts;
  final DateTime? selected;
  final ValueChanged<DateTime> onTap;
  const _DayStrip({
    required this.today,
    required this.counts,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Seven cells share the row on a phone; below 44px each they scroll
        // instead of squashing, and on wide screens they stop growing.
        const gap = 6.0;
        final cell = ((c.maxWidth - gap * (_stripDays - 1)) / _stripDays).clamp(
          44.0,
          96.0,
        );
        return SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _stripDays,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (_, i) {
              final day = today.add(Duration(days: i));
              return SizedBox(
                width: cell,
                child: _DayCell(
                  day: day,
                  isToday: i == 0,
                  count: counts[day] ?? 0,
                  selected: selected == day,
                  onTap: () => onTap(day),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isToday ? AppTheme.statusDanger : AppTheme.statusWarn;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${DateFormat('EEEE d MMMM').format(day)}, $count due',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? AppTheme.ink : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: isToday && !selected
                ? Border.all(color: AppTheme.accent, width: 1.2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('E').format(day),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white70 : AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${day.day}',
                style: AppTheme.numberStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.ink,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: count > 0 ? dotColor : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayFilterBar extends StatelessWidget {
  final VoidCallback onClear;
  const _DayFilterBar({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: const Text(
              'Showing one day only',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear day')),
        ],
      ),
    );
  }
}

// ── Overdue banner ───────────────────────────────────────────────────────────

class _OverdueBanner extends StatelessWidget {
  final List<_DueItem> items;
  const _OverdueBanner({required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (s, i) => s + (i.amount ?? 0));
    final oldest = items.fold<int>(0, (m, i) => -i.days > m ? -i.days : m);
    final n = items.length;
    // Members with no plan and no invoice have no amount to add up.
    final unknown = items.where((i) => i.amount == null).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.statusDangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL OVERDUE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppTheme.statusDanger,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCurrency(total),
                  style: AppTheme.numberStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.statusDanger,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$n member${n == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.statusDanger,
                ),
              ),
              Text(
                'oldest $oldest day${oldest == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.statusDanger,
                ),
              ),
              if (unknown > 0)
                Text(
                  '$unknown without an amount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.statusDanger,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Group + rows ─────────────────────────────────────────────────────────────

enum _Tone { overdue, today, coming }

class _DueGroup extends StatelessWidget {
  final String title;
  final List<_DueItem> items;
  final _Tone tone;
  final bool canCollect;
  final int? cap;
  final VoidCallback? onShowAll;
  final VoidCallback onCollected;
  const _DueGroup({
    required this.title,
    required this.items,
    required this.tone,
    required this.canCollect,
    required this.onCollected,
    this.cap,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (s, i) => s + (i.amount ?? 0));
    final capped = cap != null && items.length > cap!;
    final shown = capped ? items.take(cap!).toList() : items;
    final headColor = switch (tone) {
      _Tone.overdue => AppTheme.statusDanger,
      _Tone.today => AppTheme.ink,
      _Tone.coming => AppTheme.inkSoft,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title · ${items.length}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: headColor,
                    ),
                  ),
                ),
                if (total > 0)
                  Text(
                    formatCurrency(total),
                    style: AppTheme.numberStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          CardList(
            children: [
              for (final i in shown)
                _DueTile(
                  key: ValueKey(i.id),
                  item: i,
                  tone: tone,
                  canCollect: canCollect,
                  onCollected: onCollected,
                ),
              if (capped)
                InkWell(
                  onTap: onShowAll,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'Show ${items.length - cap!} more',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  final _DueItem item;
  final _Tone tone;
  final bool canCollect;
  final VoidCallback onCollected;
  const _DueTile({
    super.key,
    required this.item,
    required this.tone,
    required this.canCollect,
    required this.onCollected,
  });

  String get _when {
    final d = item.days;
    if (d < 0) return '${-d} day${d == -1 ? '' : 's'} late';
    if (d == 0) return 'due today';
    if (d == 1) return 'tomorrow';
    return 'in $d days';
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = switch (tone) {
      _Tone.overdue => AppTheme.statusDanger,
      _Tone.today => AppTheme.statusWarn,
      _Tone.coming => AppTheme.inkSoft,
    };
    final hasPhone = ((item.member['phone'] as String?) ?? '').isNotEmpty;
    return LayoutBuilder(
      builder: (context, c) {
        // Phones get the short labels; there's room for the full ones from
        // ~400px up (tablet, web).
        final roomy = c.maxWidth >= 400;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.go('/staff/members/${item.id}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          name: item.name,
                          size: 40,
                          photo: item.member['avatar_url'] as String?,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                  ),
                                  if (item.isHold) ...[
                                    const SizedBox(width: 6),
                                    const _HoldBadge(),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (item.amount != null) ...[
                                      TextSpan(
                                        text: formatCurrency(item.amount!),
                                        style: AppTheme.numberStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: toneColor,
                                        ),
                                      ),
                                      const TextSpan(text: ' · '),
                                    ],
                                    TextSpan(text: _when),
                                    if (roomy && item.planName != null)
                                      TextSpan(text: ' · ${item.planName}'),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: toneColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasPhone)
                _WhatsAppIcon(item: item)
              else
                const SizedBox(width: 4),
              if (canCollect)
                _CollectPill(
                  early: item.days > 0,
                  roomy: roomy,
                  onTap: () => showAdaptiveSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => QuickCollectSheet(
                      memberId: item.id,
                      memberName: item.name,
                    ),
                  ).then((success) {
                    if (success == true) onCollected();
                  }),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CollectPill extends StatelessWidget {
  final bool early;
  final bool roomy;
  final VoidCallback onTap;
  const _CollectPill({
    required this.early,
    required this.roomy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = early ? (roomy ? 'Collect early' : 'Early') : 'Collect';
    return Tooltip(
      message: early ? 'Collect early' : 'Collect payment',
      child: Material(
        color: early ? AppTheme.surface2 : AppTheme.accent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: early ? AppTheme.ink : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  final _DueItem item;
  const _WhatsAppIcon({required this.item});

  Future<void> _launch(BuildContext context) async {
    final phone = item.member['phone'] as String? ?? '';
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('91') ? clean : '91$clean';
    final when = formatDateFromString(_ymd(item.due));
    // A reminder for something still ahead; a plain hello for a late payment.
    final text = item.days > 0
        ? 'Hi ${item.name}, this is a reminder that your gym membership payment is due on $when. Please make the payment at the earliest. Thank you!'
        : 'Hi ${item.name}, ';
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _launch(context),
      icon: const Icon(AppIcons.chat, size: 20),
      tooltip: 'WhatsApp',
      visualDensity: VisualDensity.compact,
      color: const Color(0xFF25D366),
    );
  }
}

class _HoldBadge extends StatelessWidget {
  const _HoldBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.statusNeutralBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Hold',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.statusNeutral,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _EmptyNote({
    required this.icon,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppTheme.inkHint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.inkHint),
          ),
        ],
      ),
    );
  }
}
