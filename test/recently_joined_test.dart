import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/features/staff/members/members_screen.dart';

void main() {
  final now = DateTime(2026, 9, 12);

  group('isRecentlyJoined', () {
    test('counts a join inside the window, excludes one outside it', () {
      expect(isRecentlyJoined('2026-09-10', 7, now: now), isTrue);
      expect(isRecentlyJoined('2026-08-20', 7, now: now), isFalse);
      expect(isRecentlyJoined('2026-08-20', 30, now: now), isTrue);
    });

    test('includes both edges of the window', () {
      expect(isRecentlyJoined('2026-09-12', 7, now: now), isTrue); // today
      expect(isRecentlyJoined('2026-09-05', 7, now: now), isTrue); // exactly 7
      expect(isRecentlyJoined('2026-09-04', 7, now: now), isFalse);
    });

    test('a future join date is not recent yet', () {
      expect(isRecentlyJoined('2026-09-20', 30, now: now), isFalse);
    });

    test('survives the empty/garbage join dates the model can produce', () {
      // Member.joinedAt falls back to '' when the row has no joined_at.
      expect(isRecentlyJoined('', 30, now: now), isFalse);
      expect(isRecentlyJoined('not-a-date', 30, now: now), isFalse);
    });
  });
}
