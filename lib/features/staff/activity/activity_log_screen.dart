import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/activity_log_entry.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

final _activityEntryProvider = FutureProvider.family<ActivityLogEntry, String>((
  ref,
  id,
) async {
  final raw = await ref
      .watch(supabaseProvider)
      .rpc('get_activity_log_entry', params: {'p_entry_id': id});
  return ActivityLogEntry.fromJson(Map<String, dynamic>.from(raw as Map));
});

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String? _branchId;
  String? _actorId;
  String? _module;
  String? _action;
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _total = 0;
  List<ActivityLogEntry> _items = const [];

  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 0;
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await ref.read(myGymBranchesProvider.future);
      final gymIds = _branchId == null
          ? branches.map((row) => row['gym_id'] as String).toList()
          : [_branchId!];
      final endExclusive = DateTime(
        _range.end.year,
        _range.end.month,
        _range.end.day + 1,
      );
      final raw = await ref
          .read(supabaseProvider)
          .rpc(
            'get_activity_log',
            params: {
              'p_gym_ids': gymIds,
              'p_from': DateTime(
                _range.start.year,
                _range.start.month,
                _range.start.day,
              ).toUtc().toIso8601String(),
              'p_to': endExclusive.toUtc().toIso8601String(),
              'p_search': _searchController.text.trim(),
              'p_actor_id': _actorId,
              'p_module': _module,
              'p_action_type': _action,
              'p_limit': _pageSize,
              'p_offset': _page * _pageSize,
            },
          );
      final result = Map<String, dynamic>.from(raw as Map);
      final rows = (result['items'] as List? ?? const [])
          .map(
            (row) => ActivityLogEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _total = (result['total'] as num?)?.toInt() ?? rows.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(myGymBranchesProvider).valueOrNull ?? const [];
    final actors = <String, String>{
      for (final entry in _items)
        if (entry.actorId != null) entry.actorId!: entry.actorName,
    };
    final actions = _items.map((entry) => entry.actionType).toSet().toList()
      ..sort();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: _ActivityBackButton(fallbackRoute: '/staff/dashboard'),
        title: const Text('Activity log'),
      ),
      body: ResponsiveContent(
        child: Column(
          children: [
            Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _searchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search actor, action, or member',
                      prefixIcon: Icon(AppIcons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterButton(
                          label:
                              '${DateFormat('d MMM').format(_range.start)} – ${DateFormat('d MMM').format(_range.end)}',
                          icon: AppIcons.dateRange,
                          onTap: _pickRange,
                        ),
                        const SizedBox(width: 8),
                        _MenuFilter<String?>(
                          value: _branchId,
                          label: _branchId == null
                              ? 'All branches'
                              : branches
                                            .map((row) => row['gyms'] as Map?)
                                            .where(
                                              (gym) => gym?['id'] == _branchId,
                                            )
                                            .firstOrNull?['name']
                                        as String? ??
                                    'Branch',
                          entries: [
                            const DropdownMenuEntry(
                              value: null,
                              label: 'All branches',
                            ),
                            ...branches.map((row) {
                              final gym = row['gyms'] as Map? ?? const {};
                              return DropdownMenuEntry<String?>(
                                value: row['gym_id'] as String?,
                                label: gym['name'] as String? ?? 'Branch',
                              );
                            }),
                          ],
                          onSelected: (value) {
                            setState(() {
                              _branchId = value;
                              _page = 0;
                            });
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        _MenuFilter<String?>(
                          value: _actorId,
                          label: _actorId == null
                              ? 'All actors'
                              : actors[_actorId] ?? 'Actor',
                          entries: [
                            const DropdownMenuEntry(
                              value: null,
                              label: 'All actors',
                            ),
                            ...actors.entries.map(
                              (entry) => DropdownMenuEntry<String?>(
                                value: entry.key,
                                label: entry.value,
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            setState(() {
                              _actorId = value;
                              _page = 0;
                            });
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        _MenuFilter<String?>(
                          value: _module,
                          label: _module == null
                              ? 'All modules'
                              : _title(_module!),
                          entries: [
                            const DropdownMenuEntry(
                              value: null,
                              label: 'All modules',
                            ),
                            ...const [
                              'members',
                              'memberships',
                              'attendance',
                              'payments',
                              'reports',
                              'batches',
                              'leads',
                              'expenses',
                              'staff',
                              'settings',
                            ].map(
                              (value) => DropdownMenuEntry<String?>(
                                value: value,
                                label: _title(value),
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            setState(() {
                              _module = value;
                              _page = 0;
                            });
                            _load();
                          },
                        ),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _MenuFilter<String?>(
                            value: _action,
                            label: _action == null
                                ? 'All actions'
                                : _title(_action!),
                            entries: [
                              const DropdownMenuEntry(
                                value: null,
                                label: 'All actions',
                              ),
                              ...actions.map(
                                (value) => DropdownMenuEntry<String?>(
                                  value: value,
                                  label: _title(value),
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              setState(() {
                                _action = value;
                                _page = 0;
                              });
                              _load();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
            if (_total > _pageSize) _buildPager(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorState(what: 'the activity log', onRetry: _load);
    }
    if (_items.isEmpty) {
      return const StateMessage(
        icon: AppIcons.historyToggleOff,
        title: 'No matching activity',
        body: 'Try a wider date range or remove a filter.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              backgroundColor: AppTheme.activeBg,
              child: Icon(
                _moduleIcon(item.module),
                color: AppTheme.ink,
                size: 19,
              ),
            ),
            title: Text(
              item.actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              [
                item.actorName,
                if (item.entityLabel?.isNotEmpty == true) item.entityLabel!,
                item.branchName,
                DateFormat('d MMM, h:mm a').format(item.createdAt),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: item.amount == null
                ? const Icon(AppIcons.chevronRight, size: 18)
                : Text(
                    formatCurrency(item.amount!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
            onTap: () => context.push('/staff/activity-log/${item.id}'),
          );
        },
      ),
    );
  }

  Widget _buildPager() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: AppTheme.surface,
      border: Border(top: BorderSide(color: AppTheme.border)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${_page * _pageSize + 1}–${((_page + 1) * _pageSize).clamp(0, _total)} of $_total',
        ),
        Row(
          children: [
            IconButton(
              onPressed: _page == 0
                  ? null
                  : () {
                      setState(() => _page--);
                      _load();
                    },
              icon: const Icon(AppIcons.chevronLeft),
            ),
            IconButton(
              onPressed: (_page + 1) * _pageSize >= _total
                  ? null
                  : () {
                      setState(() => _page++);
                      _load();
                    },
              icon: const Icon(AppIcons.chevronRight),
            ),
          ],
        ),
      ],
    ),
  );
}

class ActivityLogDetailScreen extends ConsumerWidget {
  final String entryId;

  const ActivityLogDetailScreen({super.key, required this.entryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(_activityEntryProvider(entryId));
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: const _ActivityBackButton(
          fallbackRoute: '/staff/activity-log',
        ),
        title: const Text('Activity details'),
      ),
      body: ResponsiveContent(
        child: entry.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ErrorState(what: 'this activity record'),
          data: (item) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                item.actionLabel,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 20),
              _DetailRow(
                label: 'Actor',
                value: item.actorRole != null
                    ? '${item.actorName} (${_title(item.actorRole!)})'
                    : item.actorName,
              ),
              _DetailRow(
                label: 'Time',
                value: DateFormat(
                  'd MMM yyyy, h:mm:ss a',
                ).format(item.createdAt),
              ),
              _DetailRow(label: 'Module', value: _title(item.module)),
              _DetailRow(label: 'Branch', value: item.branchName),
              _DetailRow(
                label: 'Affected record',
                value: item.entityLabel ?? item.entityType,
              ),
              if (item.amount != null)
                _DetailRow(
                  label: 'Amount',
                  value: formatCurrency(item.amount!),
                ),
              if (item.metadata.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Recorded details', style: AppTheme.sectionTitle),
                const SizedBox(height: 8),
                ...item.metadata.entries.map(
                  (entry) => _DetailRow(
                    label: _title(entry.key),
                    value: _safeValue(entry.value),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityBackButton extends StatelessWidget {
  final String fallbackRoute;

  const _ActivityBackButton({required this.fallbackRoute});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(AppIcons.arrowBack),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(fallbackRoute);
      }
    },
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(label, style: const TextStyle(color: AppTheme.inkSoft)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _FilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
    icon: Icon(icon, size: 17),
    label: Text(label),
  );
}

class _MenuFilter<T> extends StatelessWidget {
  final T value;
  final String label;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;

  const _MenuFilter({
    required this.value,
    required this.label,
    required this.entries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: entries
        .map(
          (entry) => MenuItemButton(
            onPressed: () => onSelected(entry.value),
            child: Text(entry.label),
          ),
        )
        .toList(),
    builder: (context, controller, _) => OutlinedButton(
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      child: Text(label),
    ),
  );
}

String _title(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _safeValue(Object? value) {
  if (value == null) return '—';
  if (value is Map) {
    return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
  if (value is List) return value.join(', ');
  return '$value';
}

IconData _moduleIcon(String module) => switch (module) {
  'members' => AppIcons.people,
  'memberships' => AppIcons.cardMembership,
  'attendance' => AppIcons.howToReg,
  'payments' => AppIcons.payments,
  'expenses' => AppIcons.receipt,
  'staff' => AppIcons.manageAccounts,
  'settings' => AppIcons.settings,
  _ => AppIcons.history,
};
