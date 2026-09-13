import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped whenever gym-scoped data is written — a payment, a check-in, a new
/// member, a plan change.
///
/// Aggregate screens (the dashboard above all) cache their totals in a
/// provider, so a write made anywhere else left them showing stale numbers
/// until a full app restart: collect a payment on the Money screen, go back to
/// Home, and yesterday's "outstanding dues" was still on screen. An owner
/// reading that concludes the payment didn't save and collects it twice.
///
/// A single counter rather than per-screen invalidation calls: the write sites
/// don't have to know which screens exist, and a screen added later only has to
/// listen here.
final gymDataChanged = ValueNotifier<int>(0);

void notifyGymDataChanged() => gymDataChanged.value++;

/// Riverpod view of [gymDataChanged], so a list provider can simply
/// `ref.watch(gymDataVersionProvider)` and refetch on the next write instead of
/// every write site knowing which providers to invalidate.
final gymDataVersionProvider = ChangeNotifierProvider<ValueNotifier<int>>(
  (ref) => gymDataChanged,
);
