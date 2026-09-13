import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/access/gym_permissions.dart';
import 'package:gym_crm/core/shells/add_fab.dart';

void main() {
  test('members owns exactly one add, so the FAB opens it directly', () {
    final owned = addActionsForRoute('/staff/members');
    expect(owned.map((a) => a.module), [GymModule.members]);
  });

  test('money owns two adds, so the FAB has to offer a choice', () {
    final owned = addActionsForRoute('/staff/billing');
    expect(owned.map((a) => a.label), ['Invoice', 'Plan']);
  });

  test('a member detail page offers no add of its own', () {
    expect(addActionsForRoute('/staff/members/abc-123'), isEmpty);
  });

  test('screens with no add get no button', () {
    expect(addActionsForRoute('/staff/check-in'), isEmpty);
    expect(addActionsForRoute('/staff/dashboard'), isEmpty);
  });
}
