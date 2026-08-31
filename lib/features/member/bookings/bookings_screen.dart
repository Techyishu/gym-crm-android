import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/gym_class.dart';
import '../../../core/theme/app_icons.dart';

final _myBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser!;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return [];

  final data = await client
      .from('bookings')
      .select('*, class_sessions(*, classes(*))')
      .eq('member_id', member['id'])
      .neq('status', 'cancelled')
      .order('booked_at', ascending: false);

  return (data as List)
      .map((e) => Booking.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _availableSessionsProvider = FutureProvider<List<ClassSession>>((
  ref,
) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser!;

  final member = await client
      .from('members')
      .select('id, gym_id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return [];

  final data = await client
      .from('class_sessions')
      .select('*, classes!inner(*, gym_id)')
      .eq('classes.gym_id', member['gym_id'])
      .gte('starts_at', DateTime.now().toIso8601String())
      .eq('status', 'scheduled')
      .order('starts_at')
      .limit(20);

  return (data as List)
      .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
      .toList();
});

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes & Bookings'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'My Bookings'),
            Tab(text: 'Book a Class'),
          ],
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MyBookingsTab(ref: ref),
          _AvailableClassesTab(
            ref: ref,
            onBooked: () => ref.invalidate(_myBookingsProvider),
          ),
        ],
      ),
    );
  }
}

class _MyBookingsTab extends StatelessWidget {
  final WidgetRef ref;
  const _MyBookingsTab({required this.ref});

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(_myBookingsProvider);

    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'your bookings'),
      data: (list) => list.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.calendarToday,
                    size: 64,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No bookings yet',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Book a class from the next tab',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(_myBookingsProvider),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) => _BookingCard(booking: list[i]),
              ),
            ),
    );
  }
}

class _AvailableClassesTab extends StatelessWidget {
  final WidgetRef ref;
  final VoidCallback onBooked;
  const _AvailableClassesTab({required this.ref, required this.onBooked});

  Future<void> _book(BuildContext context, ClassSession session) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser!;
      final member = await client
          .from('members')
          .select('id')
          .eq('user_id', user.id)
          .single();

      await client.from('bookings').insert({
        'session_id': session.id,
        'member_id': member['id'],
        'status': 'confirmed',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class booked successfully!'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
      onBooked();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(_availableSessionsProvider);

    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'your bookings'),
      data: (list) => list.isEmpty
          ? const Center(
              child: Text(
                'No upcoming classes',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(_availableSessionsProvider),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final session = list[i];
                  final cls = session.gymClass;
                  final start = DateTime.tryParse(session.startsAt)?.toLocal();
                  final color = _parseColor(cls?.color ?? '#16A34A');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 60,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cls?.name ?? 'Class',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (start != null)
                                  Text(
                                    formatDateTime(start),
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                Text(
                                  '${cls?.durationMin ?? 60} min',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _book(context, session),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                            ),
                            child: const Text('Book'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (e) {
      debugPrint('[GymCRM] Parse booking color error for "$hex": $e');
      return AppTheme.primary;
    }
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final session = booking.session;
    final cls = session?.gymClass;
    final start = session != null
        ? DateTime.tryParse(session.startsAt)?.toLocal()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          cls?.name ?? 'Class',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: start != null ? Text(formatDateTime(start)) : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            booking.status.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
