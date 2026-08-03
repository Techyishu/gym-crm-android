import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gym_crm/core/services/review_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('counts successes and only fires on milestones', () async {
    SharedPreferences.setMockInitialValues({});

    // The Play API is a no-op in tests (isAvailable() is false), so this only
    // exercises the counting/threshold logic, which is the part that can break.
    for (var i = 0; i < 12; i++) {
      await ReviewPrompt.recordSuccess();
    }

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('review_success_count'), 12);

    expect(ReviewPrompt.isMilestone(9), isFalse);
    expect(ReviewPrompt.isMilestone(10), isTrue);
    expect(ReviewPrompt.isMilestone(11), isFalse);
    expect(ReviewPrompt.isMilestone(100), isTrue);
  });
}
