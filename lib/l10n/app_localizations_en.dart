// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get collectPaymentTitle => 'Collect Payment';

  @override
  String get enterAmount => 'Enter an amount';

  @override
  String get enterValidAmount => 'Enter a valid amount';

  @override
  String get alreadyCollectedTitle => 'Already collected today';

  @override
  String alreadyCollectedBody(String amount, String name, String time) {
    return '$amount was already collected from $name today at $time. Refresh the member before collecting another renewal.';
  }

  @override
  String get renewalDateMissing =>
      'Renewal date is missing. Refresh and try again.';

  @override
  String get paymentCollected => 'Payment collected';

  @override
  String autoFilled(String hint) {
    return 'Auto-filled: $hint';
  }

  @override
  String get partialPaymentHint =>
      'Partial payment available — you can collect less than the full amount due.';

  @override
  String get collectEarlyTitle => 'Collect renewal early?';

  @override
  String collectEarlyBody(String date, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'This renewal is due on $date (in $_temp0). Continue only if you have received an advance payment.';
  }

  @override
  String get collectAdvance => 'Collect advance';

  @override
  String get partialPaymentTitle => 'Partial payment';

  @override
  String partialPaymentBody(String entered, String remaining) {
    return 'Collecting $entered now. $remaining will remain due.';
  }

  @override
  String get okCollect => 'OK, collect';

  @override
  String get paymentDateFuture => 'Payment date cannot be in the future';

  @override
  String get validTillAfterPayment =>
      'Valid till must be after the payment date';

  @override
  String get validTillLapsed =>
      'This date has already passed, so the member will stay expired. Set Valid till to a future date.';

  @override
  String validTillPartial(String date) {
    return 'Membership will be valid till $date. The rest stays as a due.';
  }

  @override
  String validTillFull(String date) {
    return 'Membership will be valid till $date.';
  }

  @override
  String get retry => 'Retry';

  @override
  String get seeAll => 'See all';

  @override
  String get add => 'Add';

  @override
  String get addMember => 'Add member';

  @override
  String get collectPayment => 'Collect payment';

  @override
  String get collect => 'Collect';

  @override
  String get signOutTitle => 'Sign out?';

  @override
  String get signOutBody => 'You can sign back in anytime.';

  @override
  String get signOutConfirm => 'Sign out';

  @override
  String get tourMembers => 'See and manage all your gym members here.';

  @override
  String get tourCheckIn => 'Tap here to check in a member with QR scan.';

  @override
  String get tourMore =>
      'Find Leads, Classes, Staff, Reports and Settings here.';

  @override
  String get homeMoneyHint => 'Dues, payments, invoices';

  @override
  String get homeCheckInHint => 'Scan or mark attendance';

  @override
  String get trialEndsToday => 'Trial ends today';

  @override
  String trialEndsIn(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'Trial ends in $_temp0';
  }

  @override
  String get trialActive => 'Trial active';

  @override
  String planRenewsIn(String plan, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$plan plan · renews in $_temp0';
  }

  @override
  String get dashboardLoadFailed => 'Failed to load dashboard';

  @override
  String get dashboardSubtitle => 'Collections, dues, expenses and profit';

  @override
  String get gettingStarted => 'Getting started';

  @override
  String get checklistAddMembers =>
      'Add 3 members — see your dashboard come alive';

  @override
  String get checklistSetFee => 'Set your monthly fee';

  @override
  String get checklistTryCheckIn => 'Try a check-in';

  @override
  String get checklistWhatsApp => 'Turn on WhatsApp reminders';

  @override
  String get quickAddMember => 'Add\nmember';

  @override
  String get quickCollectPayment => 'Collect\npayment';

  @override
  String get quickAddLead => 'Add\nlead';

  @override
  String get noPhoneSaved => 'No phone number saved for this member';

  @override
  String get whatsappOpenFailed => 'Could not open WhatsApp';

  @override
  String get birthdaysToday => 'Birthdays today';

  @override
  String get wish => 'Wish';

  @override
  String get recentPayments => 'Recent payments';

  @override
  String get noPaymentsYet => 'No payments yet';

  @override
  String get toCollect => 'To collect';

  @override
  String get needsAttention => 'Needs attention';

  @override
  String overduePayments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overdue payments',
      one: '1 overdue payment',
    );
    return '$_temp0';
  }

  @override
  String amountPending(String amount) {
    return '$amount pending';
  }

  @override
  String membershipsDueIn7Days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count memberships',
      one: '1 membership',
    );
    return '$_temp0 due in 7 days';
  }

  @override
  String get renewBeforeLapse => 'Renew before they lapse';

  @override
  String leadsNeedFollowUp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count leads',
      one: '1 lead',
    );
    return '$_temp0 need follow-up';
  }

  @override
  String get followUpPassed => 'Follow-up date has passed';

  @override
  String checkInsWaitingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count check-ins',
      one: '1 check-in',
    );
    return '$_temp0 waiting to sync';
  }

  @override
  String get savedOfflineSync => 'Saved offline · syncs when back online';

  @override
  String get paymentDueToday => 'Payment due today';

  @override
  String get noPaymentsDueToday => 'No payments due today';

  @override
  String get collectedByMode => 'Collected by payment mode';

  @override
  String get expensesByCategory => 'Expenses by category';

  @override
  String get thisMonth => 'This month';

  @override
  String get noPaymentsThisMonth => 'No payments this month yet';

  @override
  String get noExpensesThisMonth => 'No expenses logged this month';

  @override
  String get others => 'Others';

  @override
  String todayCollected(String amount, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
    );
    return 'Today $amount · $_temp0';
  }

  @override
  String get dueIn7Days => 'Due in 7 days';

  @override
  String get lastMonth => 'Last month';

  @override
  String get collectedHint => 'collected';

  @override
  String get addExpense => 'Add expense';

  @override
  String get fullReport => 'Full report';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get required => 'Required';

  @override
  String get noPlansOnMembers => 'No plans on any member yet.';

  @override
  String get membersLoadFailed => 'Could not load members. Pull to retry.';

  @override
  String get importMembers => 'Import members';

  @override
  String get inviteMembersHint => 'Invite members to use the app';

  @override
  String get openProfile => 'Open profile';

  @override
  String get call => 'Call';

  @override
  String get noMembersHere => 'No members here';

  @override
  String get noMembersHereBody =>
      'Nobody matches this search or filter yet. Clear the filter, or add your first member with the Add button.';

  @override
  String get noPlansYet => 'No membership plans yet';

  @override
  String get noPlansYetBody =>
      'Every member needs a plan — it is what generates their invoices.';

  @override
  String get createPlan => 'Create a plan';

  @override
  String get welcomeSent => 'Welcome message sent';

  @override
  String couldNotSendReason(String reason) {
    return 'Could not send — $reason';
  }

  @override
  String get tryAgainLower => 'try again';

  @override
  String get welcomeSendFailed => 'Could not send welcome message';

  @override
  String memberAdded(String name) {
    return '$name added';
  }

  @override
  String collectRemaining(String amount) {
    return 'Collect remaining $amount';
  }

  @override
  String get sending => 'Sending…';

  @override
  String get sendWelcomeEnglish => 'Send welcome message (English)';

  @override
  String get sendWelcomeHindi => 'Send welcome message (Hindi)';

  @override
  String get welcomeNeedsOwnerPhone =>
      'Welcome messages need the gym owner\'s phone number, which isn\'t added yet. The owner can add it in Settings → Edit profile.';

  @override
  String get shareManually => 'Or share manually instead';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get createPlanFirst =>
      'Create a membership plan first — members need one to be invoiced';

  @override
  String get planNotAssigned =>
      'Member was saved but the plan could not be assigned. Open the member and choose a plan.';

  @override
  String get batchNotSet => 'Member added, but the batch could not be set.';

  @override
  String paymentNotRecorded(String amount) {
    return 'Member added, but the $amount payment was NOT recorded. Open the member and tap Collect.';
  }

  @override
  String memberIdInUse(String id) {
    return 'Member ID \"$id\" is already in use. Please use a different one.';
  }

  @override
  String get addMemberFailed => 'Failed to add member. Please try again.';

  @override
  String get choosePlan => 'Choose a plan';

  @override
  String get autoAssignHint => 'Leave empty to auto-assign';

  @override
  String get pickPlanFirst => 'Pick a membership plan first.';

  @override
  String get discountRepeats =>
      'Discount repeats on every auto-generated invoice.';

  @override
  String get moreThanPayable => 'More than the amount payable';

  @override
  String get fullAmount => 'Full amount';

  @override
  String get addMoreDetails => 'Add more details';

  @override
  String get fromThePlan => 'From the plan';

  @override
  String get memberNotFound => 'Member not found';

  @override
  String get memberNotFoundBody =>
      'This member may have been deleted from your gym.';

  @override
  String get deleteMemberTitle => 'Delete member?';

  @override
  String deleteMemberBody(String name) {
    return 'Permanently delete $name? All their data (memberships, invoices, check-ins) will be removed. This cannot be undone.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get deleteMemberFailed => 'Failed to delete member';

  @override
  String get deleteMember => 'Delete member';

  @override
  String get renew => 'Renew';

  @override
  String get renewPlanTitle => 'Renew plan?';

  @override
  String renewPlanBody(String amount, String name) {
    return 'This marks $amount as collected from $name and extends their plan by one cycle. Confirm the payment was received before continuing.';
  }

  @override
  String get planRenewed => 'Plan renewed';

  @override
  String get addPlan => 'Add plan';

  @override
  String get noActivePlan => 'No active plan';

  @override
  String get fingerprintHelper =>
      'Employee number enrolled on fingerprint machine';

  @override
  String couldNotSaveError(String error) {
    return 'Could not save: $error';
  }

  @override
  String get notEnrolledInBatch => 'Not enrolled in any batch.';

  @override
  String get noCheckInsYet => 'No check-ins yet';

  @override
  String get memberIdCopied => 'Member ID copied';

  @override
  String get sendWhatsApp => 'Send WhatsApp';

  @override
  String get typeMessage => 'Type a message…';

  @override
  String get sendOnWhatsApp => 'Send on WhatsApp';

  @override
  String get membershipOnHold => 'Membership put on hold';

  @override
  String get holdRemoved => 'Hold removed';

  @override
  String get statusUpdateFailed => 'Failed to update status';

  @override
  String get sessionExpired => 'Session expired. Please sign in again.';

  @override
  String portalInviteSent(String email) {
    return 'Portal invite sent to $email';
  }

  @override
  String get inviteSendFailed => 'Failed to send invite';

  @override
  String get cancelMembershipTitle => 'Cancel membership?';

  @override
  String cancelMembershipBody(String name) {
    return '$name\'s current plan will be cancelled. This can\'t be undone.';
  }

  @override
  String get keepPlan => 'Keep plan';

  @override
  String get cancelIt => 'Cancel it';

  @override
  String get membershipCancelled => 'Membership cancelled';

  @override
  String get cancelMembershipFailed => 'Failed to cancel membership';

  @override
  String get noFullPlans =>
      'No monthly or yearly plans. Create one in Billing first.';

  @override
  String get noActivePlans => 'No active plans. Create one in Billing first.';

  @override
  String get convertToFullPlanTitle => 'Convert to a full plan';

  @override
  String get changePlan => 'Change plan';

  @override
  String get convert => 'Convert';

  @override
  String get switchPlan => 'Switch plan';

  @override
  String get recurringDiscountBody =>
      'Fixed amount deducted from every auto-generated invoice for this member.';

  @override
  String get confirm => 'Confirm';

  @override
  String get noDiscount => 'No Discount';

  @override
  String get convertedToFullPlan => 'Converted to a full plan';

  @override
  String get planAssigned => 'Plan assigned';

  @override
  String get assignPlanFailed => 'Failed to assign plan';

  @override
  String get editDiscountBody =>
      'Fixed amount deducted from every auto-generated invoice. Set to 0 to remove.';

  @override
  String get discountUpdated => 'Discount updated';

  @override
  String get discountUpdateFailed => 'Failed to update discount';

  @override
  String get removeHold => 'Remove hold';

  @override
  String get holdMembership => 'Hold membership';

  @override
  String get convertToFullPlan => 'Convert to full plan';

  @override
  String get assignPlan => 'Assign plan';

  @override
  String editRecurringDiscount(String amount) {
    return 'Edit recurring discount ($amount off)';
  }

  @override
  String get addRecurringDiscount => 'Add recurring discount';

  @override
  String get sendPortalInvite => 'Send portal invite';

  @override
  String get cancelPlan => 'Cancel plan';

  @override
  String get startNewPlanFrom => 'Start new plan from?';

  @override
  String currentPlanActiveTill(String date) {
    return 'Their current plan is active till $date.';
  }

  @override
  String todayWithDate(String date) {
    return 'Today ($date)';
  }

  @override
  String get newPlanStartsNow =>
      'New plan starts now. Remaining days on the old plan are dropped.';

  @override
  String get newPlanStartsAfter =>
      'New plan starts after the old one ends. Nothing dropped, no gap.';

  @override
  String get discountApplied => 'Discount applied';

  @override
  String get enterValidEmail => 'Enter a valid email address';

  @override
  String get enterValidMobile => 'Enter a valid 10-digit mobile number';

  @override
  String get saveFailed => 'Failed to save. Please try again.';

  @override
  String get editMember => 'Edit member';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get moreDetails => 'More details';

  @override
  String get noActivityYet => 'No activity yet';

  @override
  String get noActivityYetBody =>
      'Changes made to this member will show up here.';

  @override
  String get noMemberPaymentsBody =>
      'Payments you collect from this member will be listed here.';

  @override
  String get selectCollectionDates => 'Select collection dates';

  @override
  String get searchByMemberName => 'Search by member name';

  @override
  String get paymentsLoadFailed => 'Could not load payments';

  @override
  String get checkConnectionRetry =>
      'Check your connection, then pull down to retry.';

  @override
  String get noMatches => 'No matches';

  @override
  String noDuesForQuery(String query) {
    return 'No dues for \"$query\" in this view.';
  }

  @override
  String nothingOverdueInDays(int days) {
    return 'Nothing overdue in the last $days days';
  }

  @override
  String get viewAllDues => 'View all dues';

  @override
  String olderDuesPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count older dues',
      one: '1 older due',
    );
    return '$_temp0 haven\'t been collected or written off yet.';
  }

  @override
  String get everyonePaid => 'Everyone has paid';

  @override
  String get everyonePaidBody =>
      'No outstanding dues today. Renewals due this week will show up here.';

  @override
  String get seeUpcomingRenewals => 'See upcoming renewals';

  @override
  String get loadingEllipsis => 'Loading…';

  @override
  String get newInvoice => 'New invoice';

  @override
  String nothingForQuery(String query) {
    return 'Nothing for \"$query\" in this tab.';
  }

  @override
  String get noPaymentsInDates => 'No payments in these dates';

  @override
  String get tryWiderRange => 'Try a wider date range.';

  @override
  String get nothingHereYet => 'Nothing here yet';

  @override
  String get paymentsAppearHere =>
      'Payments appear here as soon as you record the first one.';

  @override
  String get invoicesAppearHere => 'Invoices you raise appear here.';

  @override
  String get deleteInvoiceTitle => 'Delete invoice?';

  @override
  String get deleteInvoiceBody =>
      'This invoice and its payment records will be permanently deleted. This cannot be undone.';

  @override
  String get change => 'Change';

  @override
  String get collectEarly => 'Collect early';

  @override
  String get earlyShort => 'Early';

  @override
  String alreadyCollectedRecordAgain(
    String amount,
    String time,
    String newAmount,
  ) {
    return '$amount was already collected from this member today at $time.\n\nRecord $newAmount again?';
  }

  @override
  String get recordAnyway => 'Record anyway';

  @override
  String get paymentRecorded => 'Payment recorded';

  @override
  String get recordPayment => 'Record payment';

  @override
  String get selectMemberFirst => 'Select a member first';

  @override
  String get createInvoice => 'Create invoice';

  @override
  String get selectMember => 'Select member';

  @override
  String autoFilledFromPlan(String hint) {
    return 'Auto-filled from active plan: $hint';
  }

  @override
  String get selectDate => 'Select date';

  @override
  String get createSendInvoice => 'Create & send invoice';

  @override
  String get noPhoneAddInProfile =>
      'No phone number saved for this member. Add it in their profile first.';

  @override
  String get invoicePdfFailed => 'Could not generate or upload invoice PDF';

  @override
  String get noConnection => 'No connection';

  @override
  String get checkInNeedsInternet =>
      'Check-in needs internet on first use. Connect once to enable offline mode.';

  @override
  String get sessionExpiredShort => 'Session expired';

  @override
  String get signInForOffline =>
      'Please sign in again to use offline check-in.';

  @override
  String get savedOffline => 'Saved offline';

  @override
  String get willSyncWhenConnected => 'Will sync automatically when connected.';

  @override
  String checkedOutSuccess(String name) {
    return '$name — Checked out successfully.';
  }

  @override
  String checkoutFailed(String error) {
    return 'Checkout failed: $error';
  }

  @override
  String get invalidQr => 'Invalid QR Code';

  @override
  String get notMemberQr => 'This is not a GymCRM member QR code.';

  @override
  String get scanNext => 'Scan next';

  @override
  String get searchNameOrId => 'Search name or enter member ID';

  @override
  String get noMembersMatchName => 'No members match that name';

  @override
  String get todaysCheckIns => 'Today\'s check-ins';

  @override
  String get noCheckInsToday => 'No check-ins yet today';

  @override
  String get staffScansMember => 'Staff scans member';

  @override
  String get membersScanGym => 'Members scan gym';

  @override
  String gymQrLoadFailed(String error) {
    return 'Could not load gym QR: $error';
  }

  @override
  String get noCheckInCode => 'No check-in code for this gym yet.';

  @override
  String get membersScanThis => 'Members scan this to check themselves in';

  @override
  String get checkInLinkCopied => 'Check-in link copied';

  @override
  String get tapToCopyLink => 'Tap to copy check-in link';

  @override
  String get fullScreenFrontDesk => 'Full screen for front desk display';

  @override
  String get savedToGallery => 'Saved to gallery';

  @override
  String get qrSaveFailed => 'Could not save the QR code. Please try again.';

  @override
  String get qrShareFailed => 'Could not share the QR code. Please try again.';

  @override
  String get membersScanThisPrint =>
      'Members scan this to check themselves in.\nPrint it and place it at the front desk.';

  @override
  String get saving => 'Saving…';

  @override
  String get saveToGallery => 'Save to gallery';

  @override
  String get preparing => 'Preparing…';

  @override
  String checkInsSavedOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count check-ins',
      one: '1 check-in',
    );
    return '$_temp0 saved offline — tap to sync now';
  }

  @override
  String get checkOut => 'Check out';

  @override
  String get searchMemberName => 'Search member name...';

  @override
  String get noCheckInsFound => 'No check-ins found';

  @override
  String get featMoney => 'Money';

  @override
  String get featCheckIn => 'Check-in';

  @override
  String get featMembers => 'Members';

  @override
  String get featPlans => 'Plans';

  @override
  String get featExpenses => 'Expenses';

  @override
  String get featBiometric => 'Biometric device';

  @override
  String get featAttendance => 'Attendance calendar';

  @override
  String get featStaff => 'Staff & roles';

  @override
  String get featLeads => 'Leads';

  @override
  String get featReminders => 'Reminders';

  @override
  String get featSignupCode => 'Member signup code';

  @override
  String get featBatches => 'Batches';

  @override
  String get featWorkout => 'Workout plans';

  @override
  String get featDiet => 'Diet plans';

  @override
  String get featReports => 'Reports';

  @override
  String get featExport => 'Export data';

  @override
  String get featActivity => 'Activity log';

  @override
  String get featBranches => 'Gym branches';

  @override
  String get featSettings => 'Settings';

  @override
  String get groupRunGym => 'Run the gym';

  @override
  String get groupGrow => 'Grow';

  @override
  String get groupPrograms => 'Member programs';

  @override
  String get groupInsights => 'Insights';

  @override
  String get groupSetup => 'Setup';

  @override
  String get settingsAccount => 'ACCOUNT';

  @override
  String get settingsGym => 'GYM';

  @override
  String get settingsApp => 'APP';

  @override
  String get subscription => 'Subscription';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get changePassword => 'Change Password';

  @override
  String get tryNewDesign => 'Try the new design';

  @override
  String get switchBackClassic => 'Switch back to the classic design';

  @override
  String get gymDetails => 'Gym Details';

  @override
  String get staffRow => 'Staff';

  @override
  String get invoiceSettings => 'Invoice settings';

  @override
  String get registrationLink => 'Registration Link';

  @override
  String get rateUsAppStore => 'Rate us on the App Store';

  @override
  String get rateUsPlayStore => 'Rate us on Play Store';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get privacyChoices => 'Privacy & data choices';

  @override
  String get exportGymData => 'Export gym data';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get aboutGymCRM => 'About GymCRM';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get expenses => 'Expenses';

  @override
  String get deleteExpenseTitle => 'Delete expense?';

  @override
  String deleteExpenseBody(Object amount, Object category) {
    return 'Delete this $category entry of $amount? This cannot be undone.';
  }

  @override
  String get category => 'Category';

  @override
  String get amount => 'Amount';

  @override
  String get date => 'Date';

  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get saveExpense => 'Save expense';

  @override
  String get noExpensesLogged => 'No expenses logged';

  @override
  String get noExpensesLoggedBody =>
      'Log rent, salary, and other gym expenses here';

  @override
  String errorWithMessage(Object error) {
    return 'Error: $error';
  }

  @override
  String get staffPermissions => 'Staff permissions';

  @override
  String get ownersKeepAccess => 'Owners always keep full access';

  @override
  String get permissionSetupHint =>
      'Set defaults for a role, then override individual staff only where needed.';

  @override
  String get roleDefaults => 'Role defaults';

  @override
  String get staffOverride => 'Staff override';

  @override
  String get configureRole => 'Configure role';

  @override
  String get manager => 'Manager';

  @override
  String get trainer => 'Trainer';

  @override
  String get staff => 'Staff';

  @override
  String get noStaffToConfigure => 'No staff to configure';

  @override
  String get inviteStaffFirst =>
      'Invite a manager, trainer, or staff member first.';

  @override
  String get configureStaffMember => 'Configure staff member';

  @override
  String get useRoleDefault => 'Use role default';

  @override
  String get view => 'View';

  @override
  String get edit => 'Edit';

  @override
  String get freeze => 'Freeze';

  @override
  String get export => 'Export';

  @override
  String get ownerPermissionsLocked => 'Owner permissions cannot be reduced.';

  @override
  String get permissionDeniedStaffAccess =>
      'You don\'t have permission to change staff access.';

  @override
  String get permissionsSaveFailed =>
      'Could not save permissions. Please try again.';

  @override
  String get gymBranches => 'Gym branches';

  @override
  String branchesLoadFailed(Object error) {
    return 'Could not load branches: $error';
  }

  @override
  String get gym => 'Gym';

  @override
  String get addBranch => 'Add branch';

  @override
  String get addGymBranch => 'Add gym branch';

  @override
  String get branchName => 'Branch name';

  @override
  String get cityOptional => 'City (optional)';

  @override
  String get branchNameRequired => 'Branch name is required.';

  @override
  String get createBranch => 'Create branch';

  @override
  String get memberSignupCode => 'Member signup code';

  @override
  String get signupCodeHelp =>
      'Members enter this code — plus their phone number — to create their own portal account.';

  @override
  String get noCodeAvailable => 'No code available yet.';

  @override
  String get gymCodeCopied => 'Gym code copied';

  @override
  String get tapToCopy => 'Tap to copy';

  @override
  String get shareWithMembers => 'Share with members';

  @override
  String get attendanceCalendar => 'Attendance calendar';

  @override
  String get deleteAttendanceTitle => 'Delete attendance?';

  @override
  String permissionToActionDenied(Object action) {
    return 'You don\'t have permission to $action.';
  }

  @override
  String get noAttendanceRecorded => 'No attendance recorded';

  @override
  String get addAttendance => 'Add attendance';

  @override
  String get editCorrection => 'Edit correction';

  @override
  String get searchMember => 'Search member';

  @override
  String get member => 'Member';

  @override
  String checkInAt(Object time) {
    return 'In $time';
  }

  @override
  String get manualChangeReason => 'Reason for manual change';

  @override
  String get manualChangeHint => 'Example: biometric device was offline';

  @override
  String get saveAttendance => 'Save attendance';

  @override
  String get reason => 'Reason';

  @override
  String presentCount(Object count) {
    return '$count present';
  }

  @override
  String get attendanceEmptyHint =>
      'Choose Add attendance to record a manual correction.';

  @override
  String get correctAttendance => 'Correct attendance';

  @override
  String get selectMemberError => 'Select a member.';

  @override
  String get clearReasonError =>
      'Enter a clear reason (at least 5 characters).';

  @override
  String get noCheckout => 'No checkout';

  @override
  String checkOutAt(Object time) {
    return 'Out $time';
  }

  @override
  String get enterFiveCharacters => 'Enter at least 5 characters';

  @override
  String get leads => 'Leads';

  @override
  String get followUp => 'Follow-up';

  @override
  String get all => 'All';

  @override
  String get deleteEnquiryTitle => 'Delete enquiry?';

  @override
  String deleteEnquiryBody(Object name) {
    return 'Delete $name? This cannot be undone.';
  }

  @override
  String get updateStatus => 'Update status';

  @override
  String get addEnquiry => 'Add enquiry';

  @override
  String get phone => 'Phone';

  @override
  String get email => 'Email';

  @override
  String get source => 'Source';

  @override
  String get followUpDateOptional => 'Follow-up date (optional)';

  @override
  String get notes => 'Notes';

  @override
  String get saveEnquiry => 'Save enquiry';

  @override
  String get noLeadsYet => 'No leads yet';

  @override
  String get noLeadsYetBody =>
      'Add the people who walk in or call, and this list tells you who to follow up with each day.';

  @override
  String get reminders => 'Reminders';

  @override
  String get gymNotFound => 'Gym not found';

  @override
  String get push => 'Push';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get invoices => 'Invoices';

  @override
  String get automaticRenewalNudges =>
      'Automatic nudges before a membership expires';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get sendBeforeRenewal => 'SEND BEFORE RENEWAL';

  @override
  String get pushReminders => 'Push reminders';

  @override
  String get pushReminderSubtitle => 'In-app notification to the member';

  @override
  String get reminderWindowsHint =>
      'Reminders are sent once a day for members whose renewal date matches one of the selected windows.';

  @override
  String get whatsappReminders => 'WhatsApp reminders';

  @override
  String get whatsappReminderSubtitle =>
      'Message sent to the member\'s WhatsApp';

  @override
  String get oneMessagePerWindow =>
      'One message per member per window. Each send uses one credit.';

  @override
  String get message => 'MESSAGE';

  @override
  String get preview => 'PREVIEW';

  @override
  String get credits => 'CREDITS';

  @override
  String get sendRemindersNow => 'Send reminders now';

  @override
  String get invoiceWhatsappMessages => 'Invoice WhatsApp messages';

  @override
  String get invoiceWhatsappSubtitle =>
      'Auto-send invoice and payment receipt to the member';

  @override
  String get sameWhatsappCredits =>
      'Uses the same WhatsApp credits as reminders.';

  @override
  String get freeMonthlyQuota => 'Free monthly quota';

  @override
  String get resetsFirstMonth => 'Resets on the 1st of the month';

  @override
  String get purchasedCredits => 'Purchased credits';

  @override
  String get staffAndRoles => 'Staff and roles';

  @override
  String get permissions => 'Permissions';

  @override
  String get staffLoadFailed => 'Could not load staff. Pull down to retry.';

  @override
  String get noStaffMembers => 'No staff members yet.';

  @override
  String get inviteStaffMember => 'Invite staff member';

  @override
  String removeStaffTitle(Object name) {
    return 'Remove $name?';
  }

  @override
  String get removeStaffBody =>
      'They\'ll lose access to this gym\'s dashboard immediately.';

  @override
  String get remove => 'Remove';

  @override
  String get staffMemberRemoved => 'Staff member removed';

  @override
  String get roles => 'Roles';

  @override
  String get you => 'You';

  @override
  String get firstLastNameRequired => 'First and last name are required.';

  @override
  String get inviteStaff => 'Invite staff';

  @override
  String get inviteStaffHelp =>
      'They\'ll receive an email to set their password and log in.';

  @override
  String get role => 'Role';

  @override
  String get sendingInvite => 'Sending invite…';

  @override
  String get sendInvite => 'Send invite';

  @override
  String get classes => 'Classes';

  @override
  String get deleteBatch => 'Delete batch';

  @override
  String deleteBatchBody(Object name) {
    return 'Delete \"$name\"? All sessions and enrollments will also be removed. This cannot be undone.';
  }

  @override
  String failedToDelete(Object error) {
    return 'Failed to delete: $error';
  }

  @override
  String get addSession => 'Add session';

  @override
  String get time => 'Time';

  @override
  String capacityDuration(Object capacity, Object minutes) {
    return 'Capacity: $capacity · $minutes min';
  }

  @override
  String get hideSessions => 'Hide sessions';

  @override
  String get viewSessions => 'View sessions';

  @override
  String get noUpcomingSessions => 'No upcoming sessions';

  @override
  String get noBatchesYet => 'No batches yet';

  @override
  String get addFirstClass => 'Add your first class to get started.';

  @override
  String get addBatch => 'Add batch';

  @override
  String get editClass => 'Edit class';

  @override
  String get addClass => 'Add class';

  @override
  String get type => 'Type';

  @override
  String get coach => 'Coach';

  @override
  String get capacity => 'Capacity';

  @override
  String get duration => 'Duration';

  @override
  String get runsOn => 'Runs on';

  @override
  String get noDaysSelected =>
      'No days selected — add sessions manually from the calendar.';

  @override
  String get colour => 'Colour';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get saveClass => 'Save class';

  @override
  String get removeFromBatch => 'Remove from batch';

  @override
  String removeMemberFromBatch(Object batch, Object name) {
    return 'Remove $name from $batch?';
  }

  @override
  String get searchMembers => 'Search members';

  @override
  String get allMembersEnrolled => 'All members are already enrolled.';

  @override
  String get noMembersFound => 'No members found';

  @override
  String get enrolled => 'Enrolled';

  @override
  String get noMembersEnrolled => 'No members enrolled yet — add one above.';

  @override
  String get paymentsDue => 'Payments due';

  @override
  String get allCaughtUp => 'All caught up';

  @override
  String get noOverdueUpcoming => 'No overdue or upcoming payments right now.';

  @override
  String get nothingDueThatDay => 'Nothing due that day';

  @override
  String get pickAnotherDay => 'Pick another day or clear the filter.';

  @override
  String get overdue => 'Overdue';

  @override
  String get noOverduePayments => 'No overdue payments';

  @override
  String get everyoneUpToDate => 'Everyone is up to date.';

  @override
  String get oldestFirst => 'Oldest first';

  @override
  String get nothingDueToday => 'Nothing due today';

  @override
  String get checkComingNext => 'Check what is coming up next.';

  @override
  String get nothingComingUp => 'Nothing coming up';

  @override
  String get noPaymentsNext30Days => 'No payments due in the next 30 days.';

  @override
  String get coming => 'Coming';

  @override
  String get later => 'Later';

  @override
  String get showingOneDay => 'Showing one day only';

  @override
  String get clearDay => 'Clear day';

  @override
  String get viewExpiredMembers => 'View expired members';

  @override
  String get totalOverdue => 'TOTAL OVERDUE';

  @override
  String get firstName => 'First name';

  @override
  String get lastName => 'Last name';

  @override
  String get initialStatus => 'Initial status';

  @override
  String teamMembersCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count team members',
      one: '1 team member',
    );
    return '$_temp0';
  }

  @override
  String inviteSentTo(Object email) {
    return 'Invite sent to $email';
  }

  @override
  String get failedSendInvite => 'Failed to send invite';

  @override
  String starterStaffLimit(Object count) {
    return 'Starter includes $count login. Upgrade to Pro to add staff.';
  }

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get filterByPlan => 'Filter by plan';

  @override
  String get lapsingWithin => 'Lapsing within';

  @override
  String get joinedWithin => 'Joined within';

  @override
  String get expiringSoon => 'Expiring soon';

  @override
  String get searchMemberHint => 'Name, mobile or member ID';

  @override
  String get stepMember => '1 · MEMBER';

  @override
  String get stepMembership => '2 · MEMBERSHIP';

  @override
  String get stepPayment => '3 · PAYMENT';

  @override
  String get fullName => 'Full name';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get batch => 'Batch';

  @override
  String get memberId => 'Member ID';

  @override
  String get discount => 'Discount';

  @override
  String get amountCollected => 'Amount collected';

  @override
  String get emergencyContact => 'EMERGENCY CONTACT';

  @override
  String get name => 'Name';

  @override
  String get number => 'Number';

  @override
  String get emergencyNameHint => 'e.g. Ramesh (father)';

  @override
  String get contact => 'Contact';

  @override
  String get biometricDeviceId => 'Biometric device ID';

  @override
  String get enrolledBatches => 'Enrolled batches';

  @override
  String get recentCheckIns => 'Recent check-ins';

  @override
  String get recurringDiscount => 'Recurring discount';

  @override
  String get editRecurringDiscountTitle => 'Edit recurring discount';

  @override
  String get discountAmount => 'Discount amount';

  @override
  String get due => 'Due';

  @override
  String get dueTodayLabel => 'Due today';

  @override
  String daysOverdue(Object days) {
    return '$days days overdue';
  }

  @override
  String upcomingInDays(Object days) {
    return 'Upcoming in $days days';
  }

  @override
  String get clearDates => 'Clear dates';

  @override
  String get partlyPaid => 'partly paid';

  @override
  String get method => 'Method';

  @override
  String get notesOptional => 'Notes (optional)';

  @override
  String get admissionFeeOptional => 'Admission fee (optional)';

  @override
  String get discountOptional => 'Discount (optional)';

  @override
  String get dueDateOptional => 'Due date (optional)';

  @override
  String get deletePlanTitle => 'Delete plan?';

  @override
  String get planName => 'Plan name';

  @override
  String get price => 'Price';

  @override
  String get monthly => 'Monthly';

  @override
  String get quarterly => 'Quarterly';

  @override
  String get sixMonths => '6 months';

  @override
  String get yearly => 'Yearly';

  @override
  String get custom => 'Custom…';

  @override
  String get durationMonths => 'Duration (months)';

  @override
  String get maxClassesOptional => 'Max classes (blank = unlimited)';

  @override
  String get includes => 'Includes';

  @override
  String get addFeature => 'Add a feature';

  @override
  String get savePlan => 'Save plan';

  @override
  String get language => 'Language / भाषा';

  @override
  String get tryNewDesignTitle => 'Try the new design?';

  @override
  String get switchBackClassicTitle => 'Switch back to classic?';

  @override
  String get actionSwitch => 'Switch';

  @override
  String get switchBack => 'Switch back';

  @override
  String get designSwitchFailed => 'Could not switch design. Try again.';

  @override
  String get phoneOptional => 'Phone (optional)';

  @override
  String get saveProfile => 'Save profile';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get updatePassword => 'Update password';

  @override
  String get done => 'Done';

  @override
  String get gymName => 'Gym name';

  @override
  String get addressOptional => 'Address (optional)';

  @override
  String get websiteOptional => 'Website URL (optional)';

  @override
  String get currency => 'Currency';

  @override
  String get saveDetails => 'Save details';

  @override
  String get payments => 'Payments';

  @override
  String get keyId => 'Key ID';

  @override
  String get keySecret => 'Key secret';

  @override
  String get enterToUpdate => 'Enter to update';

  @override
  String get updateKeys => 'Update keys';

  @override
  String get connectRazorpay => 'Connect Razorpay';

  @override
  String get viewPastTickets => 'View past tickets';

  @override
  String get supportTopic => 'What\'s this about?';

  @override
  String get title => 'Title';

  @override
  String get shortIssueSummary => 'Short summary of the issue';

  @override
  String get detailsOptional => 'Details (optional)';

  @override
  String get detailsHint => 'Anything that helps us understand it';

  @override
  String get submitTicket => 'Submit ticket';

  @override
  String get myTickets => 'My tickets';

  @override
  String get regenerateLinkTitle => 'Regenerate link?';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get selfRegistrationLink => 'Self-registration link';

  @override
  String get shareLink => 'Share link';

  @override
  String get regenerateLink => 'Regenerate link';

  @override
  String get biometricDevice => 'Biometric device';

  @override
  String get pair => 'Pair';

  @override
  String get viewSetupGuide => 'View full setup guide';

  @override
  String get contactWhatsapp => 'Contact us on WhatsApp';

  @override
  String get seeProPlans => 'See Pro plans';

  @override
  String get typeDeleteConfirm => 'Type DELETE to confirm';

  @override
  String galleryOpenFailed(Object error) {
    return 'Could not open gallery: $error';
  }

  @override
  String get razorpayConnected => 'Razorpay connected';

  @override
  String get razorpayDisconnected => 'Razorpay disconnected';

  @override
  String ticketsLoadFailed(Object error) {
    return 'Could not load tickets: $error';
  }

  @override
  String copiedLabel(Object label) {
    return '$label copied';
  }

  @override
  String amountRequiredWithCurrency(Object currency) {
    return 'Amount ($currency) *';
  }

  @override
  String get error => 'Error';

  @override
  String get gymQr => 'Gym QR';

  @override
  String get checkIn => 'Check in';

  @override
  String get callTooltip => 'Call';

  @override
  String get checkoutStartFailed =>
      'Could not start checkout. Please try again.';

  @override
  String get packUnavailable => 'This pack is not available right now.';

  @override
  String get purchaseSuccessful =>
      'Purchase successful — credits will appear shortly.';

  @override
  String purchaseFailed(Object error) {
    return 'Purchase failed: $error';
  }

  @override
  String sendFailed(Object error) {
    return 'Failed to send: $error';
  }

  @override
  String get className => 'Class name';

  @override
  String removeFailed(Object error) {
    return 'Failed to remove: $error';
  }

  @override
  String get expiring => 'Expiring';

  @override
  String get joined => 'Joined';

  @override
  String get expired => 'Expired';

  @override
  String get active => 'Active';

  @override
  String get onHold => 'On hold';

  @override
  String get statusNew => 'New';

  @override
  String get statusContacted => 'Contacted';

  @override
  String get statusTrial => 'Trial';

  @override
  String get statusConverted => 'Converted';

  @override
  String get statusLost => 'Lost';

  @override
  String get sourceManual => 'Manual';

  @override
  String get sourceWebsite => 'Website';

  @override
  String get sourceReferral => 'Referral';

  @override
  String get sourceWalkIn => 'Walk-in';

  @override
  String get sourceSocial => 'Social';

  @override
  String get managerAccessHint => 'Members, classes, billing, communications';

  @override
  String get trainerAccessHint =>
      'Own classes and schedule, check-in, attendance';

  @override
  String get staffAccessHint => 'Basic access to members and check-ins';

  @override
  String daysLate(Object days) {
    return '$days days late';
  }

  @override
  String inDays(Object days) {
    return 'in $days days';
  }

  @override
  String get chooseLanguage => 'Choose your language';

  @override
  String get chooseLanguageSubtitle =>
      'Choose the language you want to use in GymCRM.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get languageChangeLater => 'You can change this later in Settings.';

  @override
  String get welcomeGymcrm => 'Welcome to GymCRM.';

  @override
  String get runAGym => 'I run a gym';

  @override
  String get gymMember => 'I\'m a gym member';

  @override
  String get needHelp => 'Need help? ';

  @override
  String get contactUs => 'Contact us';

  @override
  String get gymTeams => 'FOR GYM TEAMS';

  @override
  String get runFloorHeadline => 'Run the floor.\nOwn the day.';

  @override
  String get gymOwner => 'Gym owner';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get loginSubtitle => 'Log in to run today\'s floor.';

  @override
  String get password => 'Password';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get validEmail => 'Enter a valid email';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get login => 'Log in';

  @override
  String get loggingIn => 'Logging in…';

  @override
  String get or => 'OR';

  @override
  String get newGym => 'New gym? ';

  @override
  String get createAccount => 'Create an account';

  @override
  String get secureRecovery => 'SECURE RECOVERY';

  @override
  String get recoveryHeadline => 'Back in.\nNo stress.';

  @override
  String get resetPasswordTitle => 'Reset your password';

  @override
  String get resetPasswordHelp =>
      'Enter the email you signed up with. We will send a reset link.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get checkYourEmailLabel => 'CHECK YOUR EMAIL';

  @override
  String get resetHeadline => 'One tap\nto reset.';

  @override
  String get linkSent => 'Link sent';

  @override
  String get checkEmailPrefix => 'Check ';

  @override
  String get resetLinkExpiry =>
      ' and open the reset link. It expires in one hour.';

  @override
  String get checkSpam => 'Not in your inbox? Check spam';

  @override
  String sendAgainIn(Object seconds) {
    return ', or send it again in ${seconds}s.';
  }

  @override
  String get sendAgain => 'Send again';

  @override
  String get backToLogin => 'Back to log in';

  @override
  String get back => '← Back';

  @override
  String get buildWithGymcrm => 'BUILD WITH GYMCRM';

  @override
  String get gymOnePlace => 'Your gym.\nOne place.';

  @override
  String get createYourGym => 'Create your gym';

  @override
  String get oneMinute => 'Takes about a minute.';

  @override
  String get signupGoogle => 'Sign up with Google';

  @override
  String get gymNameRequired => 'Gym name is required';

  @override
  String get countryCurrency => 'Country and currency';

  @override
  String get yourName => 'Your name';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get mobileOptional => 'Mobile number (optional)';

  @override
  String get validMobile => 'Enter a valid mobile number';

  @override
  String get tapFlagCountry => 'Tap the flag to change country';

  @override
  String get minEightCharacters => 'Min. 8 characters';

  @override
  String get passwordEightCharacters =>
      'Password must be at least 8 characters';

  @override
  String get alreadyGymcrm => 'Already on GymCRM? ';

  @override
  String get changeEmail => '← Change email';

  @override
  String get verifyEmailLabel => 'VERIFY YOUR EMAIL';

  @override
  String get almostThere => 'Almost there.';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String get sentSixDigitCode => 'We sent a 6-digit code to\n';

  @override
  String get verify => 'Verify';

  @override
  String resendCodeIn(Object seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get resendCode => 'Resend code';

  @override
  String get codeResentEmail => 'Code resent — check your email.';

  @override
  String get weak => 'Weak';

  @override
  String get fair => 'Fair';

  @override
  String get strong => 'Strong';

  @override
  String get agreeTo => 'I agree to the ';

  @override
  String get and => ' and ';

  @override
  String get acceptTermsError =>
      'Please accept the Terms of Service and Privacy Policy to continue.';

  @override
  String get continueGoogle => 'Continue with Google';

  @override
  String get mobileAccess => 'MOBILE ACCESS';

  @override
  String get mobileAccessHeadline => 'One code.\nYou are in.';

  @override
  String get loginWithMobile => 'Log in with mobile';

  @override
  String get mobileOtpHelp => 'We\'ll text you a one-time code.';

  @override
  String get sendCode => 'Send code';

  @override
  String get otpSendFailed => 'Could not send OTP. Please try again.';

  @override
  String get codeResentSms => 'Code resent via SMS.';

  @override
  String get resendFailed => 'Could not resend code. Please try again.';

  @override
  String get incorrectCode => 'Incorrect code. Please try again.';

  @override
  String get verificationFailed => 'Verification failed. Please try again.';

  @override
  String get verifyYourNumber => 'VERIFY YOUR NUMBER';

  @override
  String get checkMessages => 'Check your messages.';

  @override
  String get enterVerificationCode => 'Enter verification code';

  @override
  String get changeNumber => 'Change number';

  @override
  String get setUpYourGym => 'Set up your gym';

  @override
  String setupStep(int step) {
    return 'Step $step of 4';
  }

  @override
  String get tellUsAboutGym => 'Tell us about your gym';

  @override
  String get membersWillSee => 'This is what members will see.';

  @override
  String get createGym => 'Create Gym';

  @override
  String get freeTrialNoCard => '3-day free trial · No credit card needed';

  @override
  String get optionalLabel => '— optional';

  @override
  String get monthlyMembership => 'Monthly membership';

  @override
  String get planNameRequired => 'Plan name is required.';

  @override
  String get planPriceRequired => 'Enter a price for this plan.';

  @override
  String get planCreateFailed => 'Could not create the plan. Please try again.';

  @override
  String get createFirstPlan => 'Create your first membership plan';

  @override
  String get createFirstPlanHelp => 'Set the plan your members will join.';

  @override
  String get billingCycle => 'Billing cycle';

  @override
  String get whatsIncluded => 'What\'s included';

  @override
  String get createPlanContinue => 'Create plan & continue';

  @override
  String get creatingPlan => 'Creating plan…';

  @override
  String get firstNameRequired => 'First name is required.';

  @override
  String get memberAddFailed => 'Could not add this member. Please try again.';

  @override
  String get addFirstMember => 'Add your first member';

  @override
  String get addFirstMemberHelp => 'You can add more members anytime.';

  @override
  String get plan => 'Plan';

  @override
  String get moreMemberDetails =>
      'More details — member ID, amount paid, notes';

  @override
  String get amountPaid => 'Amount paid';

  @override
  String get notesHint => 'Anything to remember';

  @override
  String get addingMember => 'Adding member…';

  @override
  String get skipForNow => 'Skip for now';

  @override
  String get yourGym => 'Your gym';

  @override
  String get gymReady => 'Your gym is ready';

  @override
  String get gymCreated => 'Gym created';

  @override
  String get firstPlanCreated => 'First plan created';

  @override
  String get firstMemberAdded => 'First member added';

  @override
  String get goToDashboard => 'Go to dashboard';

  @override
  String get setupReadyHelp =>
      'You can add more plans, members and staff from the dashboard.';

  @override
  String get addMenuSubtitle => 'What do you want to add?';

  @override
  String get addMenuMember => 'Member';

  @override
  String get addMenuMemberHint => 'New joining, plan and first payment';

  @override
  String get addMenuInvoice => 'Invoice';

  @override
  String get addMenuInvoiceHint => 'Bill a member for a plan or service';

  @override
  String get addMenuPlan => 'Plan';

  @override
  String get addMenuPlanHint => 'Monthly, quarterly or yearly membership';

  @override
  String get addMenuLead => 'Lead';

  @override
  String get addMenuLeadHint => 'Walk-in or enquiry to follow up';

  @override
  String get addMenuBatch => 'Batch';

  @override
  String get addMenuBatchHint =>
      'Morning, evening or a class with fixed timing';

  @override
  String get addMenuStaff => 'Staff';

  @override
  String get addMenuStaffHint => 'Invite a trainer, manager or front desk';

  @override
  String get addMenuExpense => 'Expense';

  @override
  String get addMenuExpenseHint => 'Rent, salary, equipment, utilities';

  @override
  String get saveAndAddNext => 'Save & add next';

  @override
  String get discardMemberTitle => 'Discard this member?';

  @override
  String get discardMemberBody =>
      'What you typed for this member will be lost.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';
}
