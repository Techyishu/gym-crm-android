/// Role constants and feature-gate helpers for staff RBAC.
///
/// Roles in ascending privilege order: staff < trainer < manager < owner.
/// Rules come from explicit product decisions:
///   - Billing / Leads / Messages / Reports / Settings / Staff mgmt: manager+
///   - Check-in: staff + manager + owner (NOT trainer)
///   - Classes/Batches: trainer + manager + owner (NOT staff)
///   - Member PII (email, phone): manager + owner only
///   - Member list / detail: all roles (PII fields selectively hidden)
class RoleAccess {
  static bool _isManagerOrAbove(String? role) =>
      role == 'owner' || role == 'manager';

  static bool canSeeBilling(String? role) => _isManagerOrAbove(role) || role == 'staff';
  static bool canRecordPayment(String? role) => _isManagerOrAbove(role) || role == 'staff';
  static bool canCheckIn(String? role) =>
      role == 'owner' || role == 'manager' || role == 'staff';
  static bool canSeeBatches(String? role) =>
      role == 'owner' || role == 'manager' || role == 'trainer' || role == 'staff';
  static bool canSeeLeads(String? role) => _isManagerOrAbove(role);
  static bool canSeeCommunications(String? role) => _isManagerOrAbove(role);
  static bool canSeeStaff(String? role) => _isManagerOrAbove(role);
  static bool canSeeReports(String? role) => _isManagerOrAbove(role);
  static bool canSeeSettings(String? role) => _isManagerOrAbove(role);
  static bool canSeeMemberPii(String? role) => _isManagerOrAbove(role);
  static bool canEditMembers(String? role) => _isManagerOrAbove(role);
  static bool canManageWorkoutPlans(String? role) =>
      role == 'owner' || role == 'manager' || role == 'trainer' || role == 'staff';
  static bool canManageDietPlans(String? role) =>
      role == 'owner' || role == 'manager' || role == 'trainer' || role == 'staff';
}
