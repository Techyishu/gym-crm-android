import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/billing/plan_limits.dart';

void main() {
  group('planTierOf', () {
    test('unknown and missing plans read as free, not as a paid tier', () {
      expect(planTierOf(null), PlanTier.free);
      expect(planTierOf({}), PlanTier.free);
      expect(planTierOf({'plan': 'free'}), PlanTier.free);
      // 'trial' still exists on a couple of rows and must not unlock anything.
      expect(planTierOf({'plan': 'trial'}), PlanTier.free);
    });

    test('paid tiers resolve', () {
      expect(planTierOf({'plan': 'starter'}), PlanTier.starter);
      expect(planTierOf({'plan': 'pro'}), PlanTier.pro);
      expect(planTierOf({'plan': 'elite'}), PlanTier.elite);
    });
  });

  group('limits', () {
    test('only Starter is capped', () {
      expect(memberLimit(PlanTier.starter), 100);
      expect(memberLimit(PlanTier.pro), isNull);
      expect(staffLimit(PlanTier.starter), 1);
      expect(staffLimit(PlanTier.pro), isNull);
    });

    test('whatsapp quota matches the DB and edge-function ladders', () {
      expect(whatsappQuota({'plan': 'free'}), 0);
      expect(whatsappQuota({'plan': 'starter'}), 100);
      expect(whatsappQuota({'plan': 'pro'}), 300);
      expect(whatsappQuota({'plan': 'elite'}), 1500);
    });

    test('legacy pricing overrides the tier ladder', () {
      expect(whatsappQuota({'plan': 'pro', 'legacy_pricing': true}), 100);
      expect(whatsappQuota({'plan': 'starter', 'legacy_pricing': true}), 100);
    });
  });

  group('allowsBiometric', () {
    test('biometric is the one feature Starter does not get', () {
      expect(allowsBiometric(PlanTier.starter), isFalse);
      expect(allowsBiometric(PlanTier.pro), isTrue);
      expect(allowsBiometric(PlanTier.elite), isTrue);
      // Trial gyms see the whole product, biometric included.
      expect(allowsBiometric(PlanTier.free), isTrue);
    });
  });

  group('reminderDaysLimit', () {
    test('Starter gets one offset, paid tiers get three', () {
      expect(reminderDaysLimit(PlanTier.starter), 1);
      expect(reminderDaysLimit(PlanTier.pro), 3);
    });
  });
}
