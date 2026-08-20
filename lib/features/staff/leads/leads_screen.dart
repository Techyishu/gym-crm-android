import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lead.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/responsive_content.dart';

Future<void> _dialPhone(String phone) async {
  final uri = Uri.parse('tel:$phone');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openWhatsApp(String phone, {String? text}) async {
  final clean = phone.replaceAll(RegExp(r'\D'), '');
  final number = clean.startsWith('91') ? clean : '91$clean';
  final suffix = text != null ? '?text=${Uri.encodeComponent(text)}' : '';
  await launchUrl(Uri.parse('https://wa.me/$number$suffix'),
      mode: LaunchMode.externalApplication);
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

  return (data as List).map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();
});

const _statuses = ['new', 'contacted', 'trial', 'converted', 'lost'];
const _sources = ['manual', 'website', 'referral', 'walk-in', 'social'];

// ── Status helpers ─────────────────────────────────────────────────────────────

Color _statusBg(String s) => switch (s) {
      'new'       => AppTheme.statusActiveBg,
      'contacted' => AppTheme.statusNeutralBg,
      'trial'     => AppTheme.statusWarnBg,
      'converted' => AppTheme.statusActiveBg,
      'lost'      => AppTheme.statusDangerBg,
      _           => AppTheme.activeBg,
    };

Color _statusFg(String s) => switch (s) {
      'new'       => AppTheme.statusActive,
      'contacted' => AppTheme.statusNeutral,
      'trial'     => AppTheme.statusWarn,
      'converted' => AppTheme.statusActive,
      'lost'      => AppTheme.statusDanger,
      _           => AppTheme.inkSoft,
    };

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Screen ────────────────────────────────────────────────────────────────────

class LeadsScreen extends ConsumerWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(_leadsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Enquiries'),
        leading: const BackButton(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _showAddSheet(context, ref),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add, size: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: ResponsiveContent(child: leads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyLeads();

          final counts = <String, int>{};
          for (final l in list) {
            counts[l.status] = (counts[l.status] ?? 0) + 1;
          }
          final followUpCount = list.where((l) {
            if (l.status == 'converted' || l.status == 'lost') return false;
            final fu = l.followUpAt;
            if (fu == null) return l.status == 'new';
            final d = DateTime.tryParse(fu);
            return d != null && !d.isAfter(DateTime.now());
          }).length;

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
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.schedule, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$followUpCount to follow up today',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                          const Text('GymCRM tells you exactly who to call',
                            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              _SummaryStrip(counts: counts),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_leadsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _LeadCard(
                      lead: list[i],
                      onStatusChange: (status) async {
                        await Supabase.instance.client
                            .from('leads')
                            .update({'status': status})
                            .eq('id', list[i].id);
                        ref.invalidate(_leadsProvider);
                      },
                      onDelete: () async {
                        await Supabase.instance.client
                            .from('leads')
                            .delete()
                            .eq('id', list[i].id);
                        ref.invalidate(_leadsProvider);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      )),
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
  const _SummaryStrip({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statuses.map((s) {
            final count = counts[s] ?? 0;
            final fg = _statusFg(s);
            final bg = _statusBg(s);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_capitalize(s)}  $count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Lead card ─────────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final void Function(String) onStatusChange;
  final VoidCallback onDelete;
  const _LeadCard({
    required this.lead,
    required this.onStatusChange,
    required this.onDelete,
  });

  bool get _isHot {
    try {
      return DateTime.now().difference(DateTime.parse(lead.createdAt)).inHours < 48;
    } catch (e) {
      debugPrint('[GymCRM] Parse lead date error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showStatusPicker(context),
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
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                          style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
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
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 16, color: AppTheme.inkHint),
                      onSelected: (v) async {
                        if (v == 'delete') {
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Delete enquiry?',
                            body: 'Delete ${lead.name}? This cannot be undone.',
                            confirmLabel: 'Delete',
                            icon: Icons.delete_outline,
                          );
                          if (ok == true) onDelete();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: AppTheme.statusDanger),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: AppTheme.statusDanger)),
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
                  const Icon(Icons.schedule_outlined, size: 12, color: AppTheme.statusWarn),
                  const SizedBox(width: 4),
                  Text(
                    'Follow up ${formatDateFromString(lead.followUpAt)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.statusWarn, fontWeight: FontWeight.w500),
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
                  const Icon(Icons.access_time_outlined, size: 12, color: AppTheme.inkHint),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo(lead.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                  ),
                  const Spacer(),
                  _ActionIconBtn(
                    icon: Icons.call_outlined,
                    tooltip: 'Call',
                    onTap: () => _dialPhone(lead.phone!),
                  ),
                  const SizedBox(width: 8),
                  _ActionIconBtn(
                    icon: Icons.chat_outlined,
                    tooltip: 'WhatsApp',
                    onTap: () => _openWhatsApp(lead.phone!,
                        text: 'Hi ${lead.firstName}, '),
                    color: const Color(0xFF25D366),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time_outlined, size: 12, color: AppTheme.inkHint),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo(lead.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
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
                    onStatusChange(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accentSoft : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? AppTheme.accent : AppTheme.border, width: selected ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? AppTheme.accent : Colors.transparent,
                          border: Border.all(color: selected ? AppTheme.accent : AppTheme.inkHint, width: 1.5),
                        ),
                        child: selected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 12),
                      Text(_capitalize(s),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.ink)),
                    ]),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('First name'),
                    TextFormField(controller: _firstCtrl),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Last name'),
                    TextFormField(controller: _lastCtrl),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const FieldLabel('Phone'),
            TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 14),
            const FieldLabel('Email'),
            TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            const FieldLabel('Source'),
            DropdownButtonFormField<String>(
              value: _source,
              items: _sources
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(_capitalize(s)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _source = v!),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Initial status'),
            DropdownButtonFormField<String>(
              value: _status,
              items: _statuses
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(_capitalize(s)),
                      ))
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
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _followUpAt = null),
                        )
                      : const Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(
                  _followUpAt != null
                      ? formatDateFromString(_followUpAt)
                      : 'Select date',
                  style: TextStyle(
                    color: _followUpAt != null ? AppTheme.ink : AppTheme.inkHint,
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
                          color: Colors.white, strokeWidth: 2),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No leads yet',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Add leads to track potential members',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
