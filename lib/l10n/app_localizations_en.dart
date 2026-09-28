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
}
