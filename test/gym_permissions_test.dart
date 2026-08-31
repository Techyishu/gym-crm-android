import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/access/gym_permissions.dart';

void main() {
  group('GymPermissions', () {
    test('owner defaults cannot lose access', () {
      final permissions = GymPermissions.roleDefaults('owner');

      for (final module in GymModule.values) {
        for (final action in GymAction.values) {
          expect(
            permissions.can(module, action),
            isTrue,
            reason: '${module.name}.${action.name}',
          );
        }
      }
    });

    test('staff can collect payments but cannot export them', () {
      final permissions = GymPermissions.roleDefaults('staff');

      expect(permissions.can(GymModule.payments, GymAction.add), isTrue);
      expect(permissions.can(GymModule.payments, GymAction.export), isFalse);
      expect(permissions.can(GymModule.members, GymAction.freeze), isFalse);
    });

    test('server payload overrides role assumptions', () {
      final permissions = GymPermissions.fromJson({
        'members': {
          'view': true,
          'add': false,
          'edit': true,
          'delete': false,
          'freeze': true,
          'export': false,
        },
      });

      expect(permissions.can(GymModule.members, GymAction.edit), isTrue);
      expect(permissions.can(GymModule.members, GymAction.freeze), isTrue);
      expect(permissions.can(GymModule.members, GymAction.add), isFalse);
      expect(permissions.can(GymModule.payments, GymAction.view), isFalse);
    });
  });
}
