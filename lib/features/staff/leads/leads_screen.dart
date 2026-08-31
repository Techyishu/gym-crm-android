import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lead.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../../core/theme/app_icons.dart';

Future<void> _dialPhone(String phone) async {
  final uri = Uri.parse('tel:$phone');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openWhatsApp(String phone, {String? text}) async {
  final clean = phone.replaceAll(RegExp(r'\D'), '');
  final number = clean.startsWith('91') ? clean : '91$clean';
  final suffix = text != null ? '?text=${Uri.encodeComponent(text)}' : '';
  await launchUrl(
    Uri.parse('https://wa.me/$number$suffix'),
    mode: LaunchMode.externalApplication,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _leadsProvider = FutureProvider<List<Lead>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('leads')
      .select()
      .eq('gym_id', gymId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => Lead.fromJson(e as Map<String, dynamic>))
      .toList();
});

const _statuses = ['new', 'contacted', 'trial', 'converted', 'lost'];
const _sources = ['manual', 'website', 'referral', 'walk-in', 'social'];

// ── Status helpers ─────────────────────────────────────────────────────────────

Color _statusBg(String s) => switch (s) {
  'new' => AppTheme.statusActiveBg,
  'contacted' => AppTheme.statusNeutralBg,
  'trial' => AppTheme.statusWarnBg,
  'converted' => AppTheme.statusActiveBg,
  'lost' => AppTheme.statusDangerBg,
  _ => AppTheme.activeBg,
};

Color _statusFg(String s) => switch (s) {
  'new' => AppTheme.statusActive,
  'contacted' => AppTheme.statusNeutral,
  'trial' => AppTheme.statusWarn,
  'converted' => AppTheme.statusActive,
  'lost' => AppTheme.statusDanger,
  _ => AppTheme.inkSoft,
};

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Screen ────────────────────────────────────────────────────────────────────

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  // 'followup' | one of _statuses | 'all'
  String _filter = 'followup';

  static bool _needsFollowUp(Lead l) {
    if (l.status == 'converted' || l.status == 'lost') return false;
    final fu = l.followUpAt;
    if (fu == null) return l.status == 'new';
    final d = DateTime.tryParse(fu);
    return d != null && !d.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(_leadsProvider);
    final canAdd = ref.watch(
      gymPermissionProvider((GymModule.leads, GymAction.add)),
    );
    final canEdit = ref.watch(
      gymPermissionProvider((GymModule.leads, GymAction.edit)),
    );
    final canDelete = ref.watch(
      gymPermissionProvider((GymModule.leads, GymAction.delete)),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Leads'),
        leading: const BackButton(),
        actions: [
          if (canAdd)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _showAddSheet(context, ref),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(AppIcons.add, size: 22, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: ResponsiveContent(
        child: leads.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            what: 'leads',
            onRetry: () => ref.invalidate(_leadsProvider),
          ),
          data: (list) {
            if (list.isEmpty) return const _EmptyLeads();

            final counts = <String, int>{};
            for (final l in list) {
              counts[l.status] = (counts[l.status] ?? 0) + 1;
            }
            final followUpCount = list.where(_needsFollowUp).length;
            final converted = list.where((l) => l.status == 'converted').length;
            final rate = list.isEmpty
                ? 0
                : (converted / list.length * 100).round();
            final shown = switch (_filter) {
              'all' => list,
              'followup' => list.where(_needsFollowUp).toList(),
              _ => list.where((l) => l.status == _filter).toList(),
            };

            return Column(
              children: [
                if (followUpCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              AppIcons.schedule,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$followUpCount to follow up today',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const Text(
                                  'GymCRM tells you exactly who to call',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _SummaryStrip(
                  counts: counts,
                  followUpCount: followUpCount,
                  total: list.length,
                  selected: _filter,
                  onSelect: (f) => setState(() => _filter = f),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => ref.invalidate(_leadsProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: shown.length + 1,
                      itemBuilder: (_, i) {
                        if (i == shown.length) {
                          return _ConversionInsight(
                            converted: converted,
                            total: list.length,
                            rate: rate,
                          );
                        }
                        return _LeadCard(
                          lead: shown[i],
                          onStatusChange: canEdit
                              ? (status) async {
                                  await Supabase.instance.client
                                      .from('leads')
                                      .update({'status': status})
                                      .eq('id', shown[i].id);
                                  ref.invalidate(_leadsProvider);
                                }
                              : null,
                          onDelete: canDelete
                              ? () async {
                                  await Supabase.instance.client
                                      .from('leads')
                                      .delete()
                                      .eq('id', shown[i].id);
                                  ref.invalidate(_leadsProvider);
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddLeadSheet(),
    ).then((_) => ref.invalidate(_leadsProvider));
  }
}

// ── Summary strip ─────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final Map<String, int> counts;
  final int followUpCount;
  final int total;
  final String selected;
  final ValueChanged<String> onSelect;
  const _SummaryStrip({
    required this.counts,
    required this.followUpCount,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Follow-up first — it is the only bucket that needs action today.
    final chips = <(String, String, int)>[
      ('followup', 'Follow-up', followUpCount),
      for (final s in _statuses) (s, _capitalize(s), counts[s] ?? 0),
      ('all', 'All', total),
    ];
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((c) {
            final (key, label, count) = c;
            final active = key == selected;
            final fg = active ? Colors.white : _statusFg(key);
            final bg = active ? AppTheme.ink : _statusBg(key);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(key),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$label  $count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Conversion insight footer ───────────────────────────────────────────────

class _ConversionInsight extends StatelessWidget {
  final int converted;
  final int total;
  final int rate;
  const _ConversionInsight({
    required this.converted,
    required this.total,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.insights, size: 19, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$converted of $total leads converted · $rate%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lead card ─────────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final void Function(String)? onStatusChange;
  final VoidCallback? onDelete;
  const _LeadCard({
    required this.lead,
    required this.onStatusChange,
    required this.onDelete,
  });

  bool get _isHot {
    try {
      return DateTime.now().difference(DateTime.parse(lead.createdAt)).inHours <
          48;
    } catch (e) {
      debugPrint('[GymCRM] Parse lead date error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onStatusChange == null ? null : () => _showStatusPicker(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: AppTheme.cardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + info + status + menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                InitialsAvatar(name: lead.name, size: 44),
                const SizedBox(width: 12),
                // Name + source + date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              lead.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          if (_isHot) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.statusWarnBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'HOT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.statusWarn,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${lead.source != null ? _capitalize(lead.source!) : 'Manual'} · ${timeAgo(lead.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                      if (lead.email != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          lead.email!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkHint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge + menu
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusBadge(status: lead.status),
                    const SizedBox(height: 4),
                    if (onDelete != null)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          AppIcons.moreVert,
                          size: 16,
                          color: AppTheme.inkHint,
                        ),
                        onSelected: (v) async {
                          if (v == 'delete') {
                            final ok = await showConfirmDialog(
                              context,
                              title: 'Delete enquiry?',
                              body:
                                  'Delete ${lead.name}? This cannot be undone.',
                              confirmLabel: 'Delete',
                              icon: AppIcons.delete,
                            );
                            if (ok == true) onDelete!();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  AppIcons.delete,
                                  size: 16,
                                  color: AppTheme.statusDanger,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: AppTheme.statusDanger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),

            // Notes
            if (lead.notes != null && lead.notes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                lead.notes!,
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Follow-up
            if (lead.followUpAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    AppIcons.schedule,
                    size: 12,
                    color: AppTheme.statusWarn,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Follow up ${formatDateFromString(lead.followUpAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.statusWarn,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            // Bottom row: call / WhatsApp
            if (lead.phone != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    AppIcons.accessTime,
                    size: 12,
                    color: AppTheme.inkHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo(lead.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
                  const Spacer(),
                  _ActionIconBtn(
                    icon: AppIcons.call,
                    tooltip: 'Call',
                    onTap: () => _dialPhone(lead.phone!),
                  ),
                  const SizedBox(width: 8),
                  _ActionIconBtn(
                    icon: AppIcons.chat,
                    tooltip: 'WhatsApp',
                    onTap: () => _openWhatsApp(
                      lead.phone!,
                      text: 'Hi ${lead.firstName}, ',
                    ),
                    color: const Color(0xFF25D366),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    AppIcons.accessTime,
                    size: 12,
                    color: AppTheme.inkHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo(lead.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Update status'),
            const SizedBox(height: 16),
            ..._statuses.map((s) {
              final selected = s == lead.status;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onStatusChange!(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accentSoft : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? AppTheme.accent
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? AppTheme.accent
                                  : AppTheme.inkHint,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  AppIcons.check,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _capitalize(s),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _capitalize(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusFg(status),
        ),
      ),
    );
  }
}

// ── Action icon button ─────────────────────────────────────────────────────────

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _ActionIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 16, color: c),
      ),
    );
  }
}

// ── Add Lead Sheet ─────────────────────────────────────────────────────────────

class _AddLeadSheet extends ConsumerStatefulWidget {
  const _AddLeadSheet();

  @override
  ConsumerState<_AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends ConsumerState<_AddLeadSheet> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _source = 'manual';
  String _status = 'new';
  String? _followUpAt;
  bool _loading = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFollowUp() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _followUpAt = picked.toIso8601String().split('T')[0]);
    }
  }

  Future<void> _save() async {
    if (_firstCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      await client.from('leads').insert({
        'gym_id': gymId,
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'source': _source,
        'status': _status,
        if (_followUpAt != null) 'follow_up_at': _followUpAt,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Add enquiry'),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('First name'),
                      TextFormField(controller: _firstCtrl),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Last name'),
                      TextFormField(controller: _lastCtrl),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const FieldLabel('Phone'),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            const FieldLabel('Email'),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            const FieldLabel('Source'),
            DropdownButtonFormField<String>(
              value: _source,
              items: _sources
                  .map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(_capitalize(s))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _source = v!),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Initial status'),
            DropdownButtonFormField<String>(
              value: _status,
              items: _statuses
                  .map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(_capitalize(s))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Follow-up date (optional)'),
            InkWell(
              onTap: _pickFollowUp,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  suffixIcon: _followUpAt != null
                      ? IconButton(
                          icon: const Icon(AppIcons.clear, size: 18),
                          onPressed: () => setState(() => _followUpAt = null),
                        )
                      : const Icon(AppIcons.calendarToday, size: 18),
                ),
                child: Text(
                  _followUpAt != null
                      ? formatDateFromString(_followUpAt)
                      : 'Select date',
                  style: TextStyle(
                    color: _followUpAt != null
                        ? AppTheme.ink
                        : AppTheme.inkHint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Notes'),
            TextFormField(controller: _notesCtrl, maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Save enquiry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyLeads extends StatelessWidget {
  const _EmptyLeads();

  @override
  Widget build(BuildContext context) {
    return const StateMessage(
      icon: AppIcons.personSearch,
      title: 'No leads yet',
      body:
          'Add the people who walk in or call, and this list tells you who to '
          'follow up with each day.',
    );
  }
}
