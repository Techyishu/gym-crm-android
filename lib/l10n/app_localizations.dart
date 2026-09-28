import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @collectPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Collect Payment'**
  String get collectPaymentTitle;

  /// No description provided for @enterAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get enterAmount;

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @alreadyCollectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Already collected today'**
  String get alreadyCollectedTitle;

  /// No description provided for @alreadyCollectedBody.
  ///
  /// In en, this message translates to:
  /// **'{amount} was already collected from {name} today at {time}. Refresh the member before collecting another renewal.'**
  String alreadyCollectedBody(String amount, String name, String time);

  /// No description provided for @renewalDateMissing.
  ///
  /// In en, this message translates to:
  /// **'Renewal date is missing. Refresh and try again.'**
  String get renewalDateMissing;

  /// No description provided for @paymentCollected.
  ///
  /// In en, this message translates to:
  /// **'Payment collected'**
  String get paymentCollected;

  /// No description provided for @autoFilled.
  ///
  /// In en, this message translates to:
  /// **'Auto-filled: {hint}'**
  String autoFilled(String hint);

  /// No description provided for @partialPaymentHint.
  ///
  /// In en, this message translates to:
  /// **'Partial payment available — you can collect less than the full amount due.'**
  String get partialPaymentHint;

  /// No description provided for @collectEarlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Collect renewal early?'**
  String get collectEarlyTitle;

  /// No description provided for @collectEarlyBody.
  ///
  /// In en, this message translates to:
  /// **'This renewal is due on {date} (in {days, plural, =1{1 day} other{{days} days}}). Continue only if you have received an advance payment.'**
  String collectEarlyBody(String date, int days);

  /// No description provided for @collectAdvance.
  ///
  /// In en, this message translates to:
  /// **'Collect advance'**
  String get collectAdvance;

  /// No description provided for @partialPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Partial payment'**
  String get partialPaymentTitle;

  /// No description provided for @partialPaymentBody.
  ///
  /// In en, this message translates to:
  /// **'Collecting {entered} now. {remaining} will remain due.'**
  String partialPaymentBody(String entered, String remaining);

  /// No description provided for @okCollect.
  ///
  /// In en, this message translates to:
  /// **'OK, collect'**
  String get okCollect;

  /// No description provided for @paymentDateFuture.
  ///
  /// In en, this message translates to:
  /// **'Payment date cannot be in the future'**
  String get paymentDateFuture;

  /// No description provided for @validTillAfterPayment.
  ///
  /// In en, this message translates to:
  /// **'Valid till must be after the payment date'**
  String get validTillAfterPayment;

  /// No description provided for @validTillLapsed.
  ///
  /// In en, this message translates to:
  /// **'This date has already passed, so the member will stay expired. Set Valid till to a future date.'**
  String get validTillLapsed;

  /// No description provided for @validTillPartial.
  ///
  /// In en, this message translates to:
  /// **'Membership will be valid till {date}. The rest stays as a due.'**
  String validTillPartial(String date);

  /// No description provided for @validTillFull.
  ///
  /// In en, this message translates to:
  /// **'Membership will be valid till {date}.'**
  String validTillFull(String date);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @collectPayment.
  ///
  /// In en, this message translates to:
  /// **'Collect payment'**
  String get collectPayment;

  /// No description provided for @collect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get collect;

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutTitle;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'You can sign back in anytime.'**
  String get signOutBody;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutConfirm;

  /// No description provided for @tourMembers.
  ///
  /// In en, this message translates to:
  /// **'See and manage all your gym members here.'**
  String get tourMembers;

  /// No description provided for @tourCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Tap here to check in a member with QR scan.'**
  String get tourCheckIn;

  /// No description provided for @tourMore.
  ///
  /// In en, this message translates to:
  /// **'Find Leads, Classes, Staff, Reports and Settings here.'**
  String get tourMore;

  /// No description provided for @homeMoneyHint.
  ///
  /// In en, this message translates to:
  /// **'Dues, payments, invoices'**
  String get homeMoneyHint;

  /// No description provided for @homeCheckInHint.
  ///
  /// In en, this message translates to:
  /// **'Scan or mark attendance'**
  String get homeCheckInHint;

  /// No description provided for @trialEndsToday.
  ///
  /// In en, this message translates to:
  /// **'Trial ends today'**
  String get trialEndsToday;

  /// No description provided for @trialEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Trial ends in {days, plural, =1{1 day} other{{days} days}}'**
  String trialEndsIn(int days);

  /// No description provided for @trialActive.
  ///
  /// In en, this message translates to:
  /// **'Trial active'**
  String get trialActive;

  /// No description provided for @planRenewsIn.
  ///
  /// In en, this message translates to:
  /// **'{plan} plan · renews in {days, plural, =1{1 day} other{{days} days}}'**
  String planRenewsIn(String plan, int days);

  /// No description provided for @dashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load dashboard'**
  String get dashboardLoadFailed;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Collections, dues, expenses and profit'**
  String get dashboardSubtitle;

  /// No description provided for @gettingStarted.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get gettingStarted;

  /// No description provided for @checklistAddMembers.
  ///
  /// In en, this message translates to:
  /// **'Add 3 members — see your dashboard come alive'**
  String get checklistAddMembers;

  /// No description provided for @checklistSetFee.
  ///
  /// In en, this message translates to:
  /// **'Set your monthly fee'**
  String get checklistSetFee;

  /// No description provided for @checklistTryCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Try a check-in'**
  String get checklistTryCheckIn;

  /// No description provided for @checklistWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Turn on WhatsApp reminders'**
  String get checklistWhatsApp;

  /// No description provided for @quickAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add\nmember'**
  String get quickAddMember;

  /// No description provided for @quickCollectPayment.
  ///
  /// In en, this message translates to:
  /// **'Collect\npayment'**
  String get quickCollectPayment;

  /// No description provided for @quickAddLead.
  ///
  /// In en, this message translates to:
  /// **'Add\nlead'**
  String get quickAddLead;

  /// No description provided for @noPhoneSaved.
  ///
  /// In en, this message translates to:
  /// **'No phone number saved for this member'**
  String get noPhoneSaved;

  /// No description provided for @whatsappOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open WhatsApp'**
  String get whatsappOpenFailed;

  /// No description provided for @birthdaysToday.
  ///
  /// In en, this message translates to:
  /// **'Birthdays today'**
  String get birthdaysToday;

  /// No description provided for @wish.
  ///
  /// In en, this message translates to:
  /// **'Wish'**
  String get wish;

  /// No description provided for @recentPayments.
  ///
  /// In en, this message translates to:
  /// **'Recent payments'**
  String get recentPayments;

  /// No description provided for @noPaymentsYet.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get noPaymentsYet;

  /// No description provided for @toCollect.
  ///
  /// In en, this message translates to:
  /// **'To collect'**
  String get toCollect;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @overduePayments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue payment} other{{count} overdue payments}}'**
  String overduePayments(int count);

  /// No description provided for @amountPending.
  ///
  /// In en, this message translates to:
  /// **'{amount} pending'**
  String amountPending(String amount);

  /// No description provided for @membershipsDueIn7Days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 membership} other{{count} memberships}} due in 7 days'**
  String membershipsDueIn7Days(int count);

  /// No description provided for @renewBeforeLapse.
  ///
  /// In en, this message translates to:
  /// **'Renew before they lapse'**
  String get renewBeforeLapse;

  /// No description provided for @leadsNeedFollowUp.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lead} other{{count} leads}} need follow-up'**
  String leadsNeedFollowUp(int count);

  /// No description provided for @followUpPassed.
  ///
  /// In en, this message translates to:
  /// **'Follow-up date has passed'**
  String get followUpPassed;

  /// No description provided for @checkInsWaitingSync.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 check-in} other{{count} check-ins}} waiting to sync'**
  String checkInsWaitingSync(int count);

  /// No description provided for @savedOfflineSync.
  ///
  /// In en, this message translates to:
  /// **'Saved offline · syncs when back online'**
  String get savedOfflineSync;

  /// No description provided for @paymentDueToday.
  ///
  /// In en, this message translates to:
  /// **'Payment due today'**
  String get paymentDueToday;

  /// No description provided for @noPaymentsDueToday.
  ///
  /// In en, this message translates to:
  /// **'No payments due today'**
  String get noPaymentsDueToday;

  /// No description provided for @collectedByMode.
  ///
  /// In en, this message translates to:
  /// **'Collected by payment mode'**
  String get collectedByMode;

  /// No description provided for @expensesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by category'**
  String get expensesByCategory;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @noPaymentsThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No payments this month yet'**
  String get noPaymentsThisMonth;

  /// No description provided for @noExpensesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No expenses logged this month'**
  String get noExpensesThisMonth;

  /// No description provided for @others.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get others;

  /// No description provided for @todayCollected.
  ///
  /// In en, this message translates to:
  /// **'Today {amount} · {count, plural, =1{1 payment} other{{count} payments}}'**
  String todayCollected(String amount, int count);

  /// No description provided for @dueIn7Days.
  ///
  /// In en, this message translates to:
  /// **'Due in 7 days'**
  String get dueIn7Days;

  /// No description provided for @lastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth;

  /// No description provided for @collectedHint.
  ///
  /// In en, this message translates to:
  /// **'collected'**
  String get collectedHint;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @fullReport.
  ///
  /// In en, this message translates to:
  /// **'Full report'**
  String get fullReport;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @noPlansOnMembers.
  ///
  /// In en, this message translates to:
  /// **'No plans on any member yet.'**
  String get noPlansOnMembers;

  /// No description provided for @membersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load members. Pull to retry.'**
  String get membersLoadFailed;

  /// No description provided for @importMembers.
  ///
  /// In en, this message translates to:
  /// **'Import members'**
  String get importMembers;

  /// No description provided for @inviteMembersHint.
  ///
  /// In en, this message translates to:
  /// **'Invite members to use the app'**
  String get inviteMembersHint;

  /// No description provided for @openProfile.
  ///
  /// In en, this message translates to:
  /// **'Open profile'**
  String get openProfile;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @noMembersHere.
  ///
  /// In en, this message translates to:
  /// **'No members here'**
  String get noMembersHere;

  /// No description provided for @noMembersHereBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody matches this search or filter yet. Clear the filter, or add your first member with the Add button.'**
  String get noMembersHereBody;

  /// No description provided for @noPlansYet.
  ///
  /// In en, this message translates to:
  /// **'No membership plans yet'**
  String get noPlansYet;

  /// No description provided for @noPlansYetBody.
  ///
  /// In en, this message translates to:
  /// **'Every member needs a plan — it is what generates their invoices.'**
  String get noPlansYetBody;

  /// No description provided for @createPlan.
  ///
  /// In en, this message translates to:
  /// **'Create a plan'**
  String get createPlan;

  /// No description provided for @welcomeSent.
  ///
  /// In en, this message translates to:
  /// **'Welcome message sent'**
  String get welcomeSent;

  /// No description provided for @couldNotSendReason.
  ///
  /// In en, this message translates to:
  /// **'Could not send — {reason}'**
  String couldNotSendReason(String reason);

  /// No description provided for @tryAgainLower.
  ///
  /// In en, this message translates to:
  /// **'try again'**
  String get tryAgainLower;

  /// No description provided for @welcomeSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send welcome message'**
  String get welcomeSendFailed;

  /// No description provided for @memberAdded.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String memberAdded(String name);

  /// No description provided for @collectRemaining.
  ///
  /// In en, this message translates to:
  /// **'Collect remaining {amount}'**
  String collectRemaining(String amount);

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @sendWelcomeEnglish.
  ///
  /// In en, this message translates to:
  /// **'Send welcome message (English)'**
  String get sendWelcomeEnglish;

  /// No description provided for @sendWelcomeHindi.
  ///
  /// In en, this message translates to:
  /// **'Send welcome message (Hindi)'**
  String get sendWelcomeHindi;

  /// No description provided for @welcomeNeedsOwnerPhone.
  ///
  /// In en, this message translates to:
  /// **'Welcome messages need the gym owner\'s phone number, which isn\'t added yet. The owner can add it in Settings → Edit profile.'**
  String get welcomeNeedsOwnerPhone;

  /// No description provided for @shareManually.
  ///
  /// In en, this message translates to:
  /// **'Or share manually instead'**
  String get shareManually;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// No description provided for @createPlanFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a membership plan first — members need one to be invoiced'**
  String get createPlanFirst;

  /// No description provided for @planNotAssigned.
  ///
  /// In en, this message translates to:
  /// **'Member was saved but the plan could not be assigned. Open the member and choose a plan.'**
  String get planNotAssigned;

  /// No description provided for @batchNotSet.
  ///
  /// In en, this message translates to:
  /// **'Member added, but the batch could not be set.'**
  String get batchNotSet;

  /// No description provided for @paymentNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Member added, but the {amount} payment was NOT recorded. Open the member and tap Collect.'**
  String paymentNotRecorded(String amount);

  /// No description provided for @memberIdInUse.
  ///
  /// In en, this message translates to:
  /// **'Member ID \"{id}\" is already in use. Please use a different one.'**
  String memberIdInUse(String id);

  /// No description provided for @addMemberFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add member. Please try again.'**
  String get addMemberFailed;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan'**
  String get choosePlan;

  /// No description provided for @autoAssignHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to auto-assign'**
  String get autoAssignHint;

  /// No description provided for @pickPlanFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a membership plan first.'**
  String get pickPlanFirst;

  /// No description provided for @discountRepeats.
  ///
  /// In en, this message translates to:
  /// **'Discount repeats on every auto-generated invoice.'**
  String get discountRepeats;

  /// No description provided for @moreThanPayable.
  ///
  /// In en, this message translates to:
  /// **'More than the amount payable'**
  String get moreThanPayable;

  /// No description provided for @fullAmount.
  ///
  /// In en, this message translates to:
  /// **'Full amount'**
  String get fullAmount;

  /// No description provided for @addMoreDetails.
  ///
  /// In en, this message translates to:
  /// **'Add more details'**
  String get addMoreDetails;

  /// No description provided for @fromThePlan.
  ///
  /// In en, this message translates to:
  /// **'From the plan'**
  String get fromThePlan;

  /// No description provided for @memberNotFound.
  ///
  /// In en, this message translates to:
  /// **'Member not found'**
  String get memberNotFound;

  /// No description provided for @memberNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'This member may have been deleted from your gym.'**
  String get memberNotFoundBody;

  /// No description provided for @deleteMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete member?'**
  String get deleteMemberTitle;

  /// No description provided for @deleteMemberBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {name}? All their data (memberships, invoices, check-ins) will be removed. This cannot be undone.'**
  String deleteMemberBody(String name);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteMemberFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete member'**
  String get deleteMemberFailed;

  /// No description provided for @deleteMember.
  ///
  /// In en, this message translates to:
  /// **'Delete member'**
  String get deleteMember;

  /// No description provided for @renew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renew;

  /// No description provided for @renewPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Renew plan?'**
  String get renewPlanTitle;

  /// No description provided for @renewPlanBody.
  ///
  /// In en, this message translates to:
  /// **'This marks {amount} as collected from {name} and extends their plan by one cycle. Confirm the payment was received before continuing.'**
  String renewPlanBody(String amount, String name);

  /// No description provided for @planRenewed.
  ///
  /// In en, this message translates to:
  /// **'Plan renewed'**
  String get planRenewed;

  /// No description provided for @addPlan.
  ///
  /// In en, this message translates to:
  /// **'Add plan'**
  String get addPlan;

  /// No description provided for @noActivePlan.
  ///
  /// In en, this message translates to:
  /// **'No active plan'**
  String get noActivePlan;

  /// No description provided for @fingerprintHelper.
  ///
  /// In en, this message translates to:
  /// **'Employee number enrolled on fingerprint machine'**
  String get fingerprintHelper;

  /// No description provided for @couldNotSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String couldNotSaveError(String error);

  /// No description provided for @notEnrolledInBatch.
  ///
  /// In en, this message translates to:
  /// **'Not enrolled in any batch.'**
  String get notEnrolledInBatch;

  /// No description provided for @noCheckInsYet.
  ///
  /// In en, this message translates to:
  /// **'No check-ins yet'**
  String get noCheckInsYet;

  /// No description provided for @memberIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Member ID copied'**
  String get memberIdCopied;

  /// No description provided for @sendWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send WhatsApp'**
  String get sendWhatsApp;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get typeMessage;

  /// No description provided for @sendOnWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send on WhatsApp'**
  String get sendOnWhatsApp;

  /// No description provided for @membershipOnHold.
  ///
  /// In en, this message translates to:
  /// **'Membership put on hold'**
  String get membershipOnHold;

  /// No description provided for @holdRemoved.
  ///
  /// In en, this message translates to:
  /// **'Hold removed'**
  String get holdRemoved;

  /// No description provided for @statusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update status'**
  String get statusUpdateFailed;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please sign in again.'**
  String get sessionExpired;

  /// No description provided for @portalInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Portal invite sent to {email}'**
  String portalInviteSent(String email);

  /// No description provided for @inviteSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send invite'**
  String get inviteSendFailed;

  /// No description provided for @cancelMembershipTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel membership?'**
  String get cancelMembershipTitle;

  /// No description provided for @cancelMembershipBody.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s current plan will be cancelled. This can\'t be undone.'**
  String cancelMembershipBody(String name);

  /// No description provided for @keepPlan.
  ///
  /// In en, this message translates to:
  /// **'Keep plan'**
  String get keepPlan;

  /// No description provided for @cancelIt.
  ///
  /// In en, this message translates to:
  /// **'Cancel it'**
  String get cancelIt;

  /// No description provided for @membershipCancelled.
  ///
  /// In en, this message translates to:
  /// **'Membership cancelled'**
  String get membershipCancelled;

  /// No description provided for @cancelMembershipFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel membership'**
  String get cancelMembershipFailed;

  /// No description provided for @noFullPlans.
  ///
  /// In en, this message translates to:
  /// **'No monthly or yearly plans. Create one in Billing first.'**
  String get noFullPlans;

  /// No description provided for @noActivePlans.
  ///
  /// In en, this message translates to:
  /// **'No active plans. Create one in Billing first.'**
  String get noActivePlans;

  /// No description provided for @convertToFullPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert to a full plan'**
  String get convertToFullPlanTitle;

  /// No description provided for @changePlan.
  ///
  /// In en, this message translates to:
  /// **'Change plan'**
  String get changePlan;

  /// No description provided for @convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convert;

  /// No description provided for @switchPlan.
  ///
  /// In en, this message translates to:
  /// **'Switch plan'**
  String get switchPlan;

  /// No description provided for @recurringDiscountBody.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount deducted from every auto-generated invoice for this member.'**
  String get recurringDiscountBody;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @noDiscount.
  ///
  /// In en, this message translates to:
  /// **'No Discount'**
  String get noDiscount;

  /// No description provided for @convertedToFullPlan.
  ///
  /// In en, this message translates to:
  /// **'Converted to a full plan'**
  String get convertedToFullPlan;

  /// No description provided for @planAssigned.
  ///
  /// In en, this message translates to:
  /// **'Plan assigned'**
  String get planAssigned;

  /// No description provided for @assignPlanFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to assign plan'**
  String get assignPlanFailed;

  /// No description provided for @editDiscountBody.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount deducted from every auto-generated invoice. Set to 0 to remove.'**
  String get editDiscountBody;

  /// No description provided for @discountUpdated.
  ///
  /// In en, this message translates to:
  /// **'Discount updated'**
  String get discountUpdated;

  /// No description provided for @discountUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update discount'**
  String get discountUpdateFailed;

  /// No description provided for @removeHold.
  ///
  /// In en, this message translates to:
  /// **'Remove hold'**
  String get removeHold;

  /// No description provided for @holdMembership.
  ///
  /// In en, this message translates to:
  /// **'Hold membership'**
  String get holdMembership;

  /// No description provided for @convertToFullPlan.
  ///
  /// In en, this message translates to:
  /// **'Convert to full plan'**
  String get convertToFullPlan;

  /// No description provided for @assignPlan.
  ///
  /// In en, this message translates to:
  /// **'Assign plan'**
  String get assignPlan;

  /// No description provided for @editRecurringDiscount.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring discount ({amount} off)'**
  String editRecurringDiscount(String amount);

  /// No description provided for @addRecurringDiscount.
  ///
  /// In en, this message translates to:
  /// **'Add recurring discount'**
  String get addRecurringDiscount;

  /// No description provided for @sendPortalInvite.
  ///
  /// In en, this message translates to:
  /// **'Send portal invite'**
  String get sendPortalInvite;

  /// No description provided for @cancelPlan.
  ///
  /// In en, this message translates to:
  /// **'Cancel plan'**
  String get cancelPlan;

  /// No description provided for @startNewPlanFrom.
  ///
  /// In en, this message translates to:
  /// **'Start new plan from?'**
  String get startNewPlanFrom;

  /// No description provided for @currentPlanActiveTill.
  ///
  /// In en, this message translates to:
  /// **'Their current plan is active till {date}.'**
  String currentPlanActiveTill(String date);

  /// No description provided for @todayWithDate.
  ///
  /// In en, this message translates to:
  /// **'Today ({date})'**
  String todayWithDate(String date);

  /// No description provided for @newPlanStartsNow.
  ///
  /// In en, this message translates to:
  /// **'New plan starts now. Remaining days on the old plan are dropped.'**
  String get newPlanStartsNow;

  /// No description provided for @newPlanStartsAfter.
  ///
  /// In en, this message translates to:
  /// **'New plan starts after the old one ends. Nothing dropped, no gap.'**
  String get newPlanStartsAfter;

  /// No description provided for @discountApplied.
  ///
  /// In en, this message translates to:
  /// **'Discount applied'**
  String get discountApplied;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get enterValidEmail;

  /// No description provided for @enterValidMobile.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit mobile number'**
  String get enterValidMobile;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save. Please try again.'**
  String get saveFailed;

  /// No description provided for @editMember.
  ///
  /// In en, this message translates to:
  /// **'Edit member'**
  String get editMember;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @moreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get moreDetails;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @noActivityYetBody.
  ///
  /// In en, this message translates to:
  /// **'Changes made to this member will show up here.'**
  String get noActivityYetBody;

  /// No description provided for @noMemberPaymentsBody.
  ///
  /// In en, this message translates to:
  /// **'Payments you collect from this member will be listed here.'**
  String get noMemberPaymentsBody;

  /// No description provided for @selectCollectionDates.
  ///
  /// In en, this message translates to:
  /// **'Select collection dates'**
  String get selectCollectionDates;

  /// No description provided for @searchByMemberName.
  ///
  /// In en, this message translates to:
  /// **'Search by member name'**
  String get searchByMemberName;

  /// No description provided for @paymentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load payments'**
  String get paymentsLoadFailed;

  /// No description provided for @checkConnectionRetry.
  ///
  /// In en, this message translates to:
  /// **'Check your connection, then pull down to retry.'**
  String get checkConnectionRetry;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @noDuesForQuery.
  ///
  /// In en, this message translates to:
  /// **'No dues for \"{query}\" in this view.'**
  String noDuesForQuery(String query);

  /// No description provided for @nothingOverdueInDays.
  ///
  /// In en, this message translates to:
  /// **'Nothing overdue in the last {days} days'**
  String nothingOverdueInDays(int days);

  /// No description provided for @viewAllDues.
  ///
  /// In en, this message translates to:
  /// **'View all dues'**
  String get viewAllDues;

  /// No description provided for @olderDuesPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 older due} other{{count} older dues}} haven\'t been collected or written off yet.'**
  String olderDuesPending(int count);

  /// No description provided for @everyonePaid.
  ///
  /// In en, this message translates to:
  /// **'Everyone has paid'**
  String get everyonePaid;

  /// No description provided for @everyonePaidBody.
  ///
  /// In en, this message translates to:
  /// **'No outstanding dues today. Renewals due this week will show up here.'**
  String get everyonePaidBody;

  /// No description provided for @seeUpcomingRenewals.
  ///
  /// In en, this message translates to:
  /// **'See upcoming renewals'**
  String get seeUpcomingRenewals;

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingEllipsis;

  /// No description provided for @newInvoice.
  ///
  /// In en, this message translates to:
  /// **'New invoice'**
  String get newInvoice;

  /// No description provided for @nothingForQuery.
  ///
  /// In en, this message translates to:
  /// **'Nothing for \"{query}\" in this tab.'**
  String nothingForQuery(String query);

  /// No description provided for @noPaymentsInDates.
  ///
  /// In en, this message translates to:
  /// **'No payments in these dates'**
  String get noPaymentsInDates;

  /// No description provided for @tryWiderRange.
  ///
  /// In en, this message translates to:
  /// **'Try a wider date range.'**
  String get tryWiderRange;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get nothingHereYet;

  /// No description provided for @paymentsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Payments appear here as soon as you record the first one.'**
  String get paymentsAppearHere;

  /// No description provided for @invoicesAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Invoices you raise appear here.'**
  String get invoicesAppearHere;

  /// No description provided for @deleteInvoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete invoice?'**
  String get deleteInvoiceTitle;

  /// No description provided for @deleteInvoiceBody.
  ///
  /// In en, this message translates to:
  /// **'This invoice and its payment records will be permanently deleted. This cannot be undone.'**
  String get deleteInvoiceBody;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @collectEarly.
  ///
  /// In en, this message translates to:
  /// **'Collect early'**
  String get collectEarly;

  /// No description provided for @earlyShort.
  ///
  /// In en, this message translates to:
  /// **'Early'**
  String get earlyShort;

  /// No description provided for @alreadyCollectedRecordAgain.
  ///
  /// In en, this message translates to:
  /// **'{amount} was already collected from this member today at {time}.\n\nRecord {newAmount} again?'**
  String alreadyCollectedRecordAgain(
    String amount,
    String time,
    String newAmount,
  );

  /// No description provided for @recordAnyway.
  ///
  /// In en, this message translates to:
  /// **'Record anyway'**
  String get recordAnyway;

  /// No description provided for @paymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get paymentRecorded;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @selectMemberFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a member first'**
  String get selectMemberFirst;

  /// No description provided for @createInvoice.
  ///
  /// In en, this message translates to:
  /// **'Create invoice'**
  String get createInvoice;

  /// No description provided for @selectMember.
  ///
  /// In en, this message translates to:
  /// **'Select member'**
  String get selectMember;

  /// No description provided for @autoFilledFromPlan.
  ///
  /// In en, this message translates to:
  /// **'Auto-filled from active plan: {hint}'**
  String autoFilledFromPlan(String hint);

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @createSendInvoice.
  ///
  /// In en, this message translates to:
  /// **'Create & send invoice'**
  String get createSendInvoice;

  /// No description provided for @noPhoneAddInProfile.
  ///
  /// In en, this message translates to:
  /// **'No phone number saved for this member. Add it in their profile first.'**
  String get noPhoneAddInProfile;

  /// No description provided for @invoicePdfFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not generate or upload invoice PDF'**
  String get invoicePdfFailed;

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get noConnection;

  /// No description provided for @checkInNeedsInternet.
  ///
  /// In en, this message translates to:
  /// **'Check-in needs internet on first use. Connect once to enable offline mode.'**
  String get checkInNeedsInternet;

  /// No description provided for @sessionExpiredShort.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get sessionExpiredShort;

  /// No description provided for @signInForOffline.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again to use offline check-in.'**
  String get signInForOffline;

  /// No description provided for @savedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved offline'**
  String get savedOffline;

  /// No description provided for @willSyncWhenConnected.
  ///
  /// In en, this message translates to:
  /// **'Will sync automatically when connected.'**
  String get willSyncWhenConnected;

  /// No description provided for @checkedOutSuccess.
  ///
  /// In en, this message translates to:
  /// **'{name} — Checked out successfully.'**
  String checkedOutSuccess(String name);

  /// No description provided for @checkoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Checkout failed: {error}'**
  String checkoutFailed(String error);

  /// No description provided for @invalidQr.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR Code'**
  String get invalidQr;

  /// No description provided for @notMemberQr.
  ///
  /// In en, this message translates to:
  /// **'This is not a GymCRM member QR code.'**
  String get notMemberQr;

  /// No description provided for @scanNext.
  ///
  /// In en, this message translates to:
  /// **'Scan next'**
  String get scanNext;

  /// No description provided for @searchNameOrId.
  ///
  /// In en, this message translates to:
  /// **'Search name or enter member ID'**
  String get searchNameOrId;

  /// No description provided for @noMembersMatchName.
  ///
  /// In en, this message translates to:
  /// **'No members match that name'**
  String get noMembersMatchName;

  /// No description provided for @todaysCheckIns.
  ///
  /// In en, this message translates to:
  /// **'Today\'s check-ins'**
  String get todaysCheckIns;

  /// No description provided for @noCheckInsToday.
  ///
  /// In en, this message translates to:
  /// **'No check-ins yet today'**
  String get noCheckInsToday;

  /// No description provided for @staffScansMember.
  ///
  /// In en, this message translates to:
  /// **'Staff scans member'**
  String get staffScansMember;

  /// No description provided for @membersScanGym.
  ///
  /// In en, this message translates to:
  /// **'Members scan gym'**
  String get membersScanGym;

  /// No description provided for @gymQrLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load gym QR: {error}'**
  String gymQrLoadFailed(String error);

  /// No description provided for @noCheckInCode.
  ///
  /// In en, this message translates to:
  /// **'No check-in code for this gym yet.'**
  String get noCheckInCode;

  /// No description provided for @membersScanThis.
  ///
  /// In en, this message translates to:
  /// **'Members scan this to check themselves in'**
  String get membersScanThis;

  /// No description provided for @checkInLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Check-in link copied'**
  String get checkInLinkCopied;

  /// No description provided for @tapToCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy check-in link'**
  String get tapToCopyLink;

  /// No description provided for @fullScreenFrontDesk.
  ///
  /// In en, this message translates to:
  /// **'Full screen for front desk display'**
  String get fullScreenFrontDesk;

  /// No description provided for @savedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to gallery'**
  String get savedToGallery;

  /// No description provided for @qrSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the QR code. Please try again.'**
  String get qrSaveFailed;

  /// No description provided for @qrShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share the QR code. Please try again.'**
  String get qrShareFailed;

  /// No description provided for @membersScanThisPrint.
  ///
  /// In en, this message translates to:
  /// **'Members scan this to check themselves in.\nPrint it and place it at the front desk.'**
  String get membersScanThisPrint;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get saveToGallery;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @checkInsSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 check-in} other{{count} check-ins}} saved offline — tap to sync now'**
  String checkInsSavedOffline(int count);

  /// No description provided for @checkOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get checkOut;

  /// No description provided for @searchMemberName.
  ///
  /// In en, this message translates to:
  /// **'Search member name...'**
  String get searchMemberName;

  /// No description provided for @noCheckInsFound.
  ///
  /// In en, this message translates to:
  /// **'No check-ins found'**
  String get noCheckInsFound;

  /// No description provided for @featMoney.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get featMoney;

  /// No description provided for @featCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get featCheckIn;

  /// No description provided for @featMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get featMembers;

  /// No description provided for @featPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get featPlans;

  /// No description provided for @featExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get featExpenses;

  /// No description provided for @featBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometric device'**
  String get featBiometric;

  /// No description provided for @featAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance calendar'**
  String get featAttendance;

  /// No description provided for @featStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff & roles'**
  String get featStaff;

  /// No description provided for @featLeads.
  ///
  /// In en, this message translates to:
  /// **'Leads'**
  String get featLeads;

  /// No description provided for @featReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get featReminders;

  /// No description provided for @featSignupCode.
  ///
  /// In en, this message translates to:
  /// **'Member signup code'**
  String get featSignupCode;

  /// No description provided for @featBatches.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get featBatches;

  /// No description provided for @featWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout plans'**
  String get featWorkout;

  /// No description provided for @featDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet plans'**
  String get featDiet;

  /// No description provided for @featReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get featReports;

  /// No description provided for @featExport.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get featExport;

  /// No description provided for @featActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get featActivity;

  /// No description provided for @featBranches.
  ///
  /// In en, this message translates to:
  /// **'Gym branches'**
  String get featBranches;

  /// No description provided for @featSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get featSettings;

  /// No description provided for @groupRunGym.
  ///
  /// In en, this message translates to:
  /// **'Run the gym'**
  String get groupRunGym;

  /// No description provided for @groupGrow.
  ///
  /// In en, this message translates to:
  /// **'Grow'**
  String get groupGrow;

  /// No description provided for @groupPrograms.
  ///
  /// In en, this message translates to:
  /// **'Member programs'**
  String get groupPrograms;

  /// No description provided for @groupInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get groupInsights;

  /// No description provided for @groupSetup.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get groupSetup;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get settingsAccount;

  /// No description provided for @settingsGym.
  ///
  /// In en, this message translates to:
  /// **'GYM'**
  String get settingsGym;

  /// No description provided for @settingsApp.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get settingsApp;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @tryNewDesign.
  ///
  /// In en, this message translates to:
  /// **'Try the new design'**
  String get tryNewDesign;

  /// No description provided for @switchBackClassic.
  ///
  /// In en, this message translates to:
  /// **'Switch back to the classic design'**
  String get switchBackClassic;

  /// No description provided for @gymDetails.
  ///
  /// In en, this message translates to:
  /// **'Gym Details'**
  String get gymDetails;

  /// No description provided for @staffRow.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffRow;

  /// No description provided for @invoiceSettings.
  ///
  /// In en, this message translates to:
  /// **'Invoice settings'**
  String get invoiceSettings;

  /// No description provided for @registrationLink.
  ///
  /// In en, this message translates to:
  /// **'Registration Link'**
  String get registrationLink;

  /// No description provided for @rateUsAppStore.
  ///
  /// In en, this message translates to:
  /// **'Rate us on the App Store'**
  String get rateUsAppStore;

  /// No description provided for @rateUsPlayStore.
  ///
  /// In en, this message translates to:
  /// **'Rate us on Play Store'**
  String get rateUsPlayStore;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @privacyChoices.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data choices'**
  String get privacyChoices;

  /// No description provided for @exportGymData.
  ///
  /// In en, this message translates to:
  /// **'Export gym data'**
  String get exportGymData;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @aboutGymCRM.
  ///
  /// In en, this message translates to:
  /// **'About GymCRM'**
  String get aboutGymCRM;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get languageHindi;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @deleteExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense?'**
  String get deleteExpenseTitle;

  /// No description provided for @deleteExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this {category} entry of {amount}? This cannot be undone.'**
  String deleteExpenseBody(Object amount, Object category);

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @noteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// No description provided for @saveExpense.
  ///
  /// In en, this message translates to:
  /// **'Save expense'**
  String get saveExpense;

  /// No description provided for @noExpensesLogged.
  ///
  /// In en, this message translates to:
  /// **'No expenses logged'**
  String get noExpensesLogged;

  /// No description provided for @noExpensesLoggedBody.
  ///
  /// In en, this message translates to:
  /// **'Log rent, salary, and other gym expenses here'**
  String get noExpensesLoggedBody;

  /// No description provided for @errorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithMessage(Object error);

  /// No description provided for @staffPermissions.
  ///
  /// In en, this message translates to:
  /// **'Staff permissions'**
  String get staffPermissions;

  /// No description provided for @ownersKeepAccess.
  ///
  /// In en, this message translates to:
  /// **'Owners always keep full access'**
  String get ownersKeepAccess;

  /// No description provided for @permissionSetupHint.
  ///
  /// In en, this message translates to:
  /// **'Set defaults for a role, then override individual staff only where needed.'**
  String get permissionSetupHint;

  /// No description provided for @roleDefaults.
  ///
  /// In en, this message translates to:
  /// **'Role defaults'**
  String get roleDefaults;

  /// No description provided for @staffOverride.
  ///
  /// In en, this message translates to:
  /// **'Staff override'**
  String get staffOverride;

  /// No description provided for @configureRole.
  ///
  /// In en, this message translates to:
  /// **'Configure role'**
  String get configureRole;

  /// No description provided for @manager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get manager;

  /// No description provided for @trainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get trainer;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// No description provided for @noStaffToConfigure.
  ///
  /// In en, this message translates to:
  /// **'No staff to configure'**
  String get noStaffToConfigure;

  /// No description provided for @inviteStaffFirst.
  ///
  /// In en, this message translates to:
  /// **'Invite a manager, trainer, or staff member first.'**
  String get inviteStaffFirst;

  /// No description provided for @configureStaffMember.
  ///
  /// In en, this message translates to:
  /// **'Configure staff member'**
  String get configureStaffMember;

  /// No description provided for @useRoleDefault.
  ///
  /// In en, this message translates to:
  /// **'Use role default'**
  String get useRoleDefault;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @freeze.
  ///
  /// In en, this message translates to:
  /// **'Freeze'**
  String get freeze;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @ownerPermissionsLocked.
  ///
  /// In en, this message translates to:
  /// **'Owner permissions cannot be reduced.'**
  String get ownerPermissionsLocked;

  /// No description provided for @permissionDeniedStaffAccess.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to change staff access.'**
  String get permissionDeniedStaffAccess;

  /// No description provided for @permissionsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save permissions. Please try again.'**
  String get permissionsSaveFailed;

  /// No description provided for @gymBranches.
  ///
  /// In en, this message translates to:
  /// **'Gym branches'**
  String get gymBranches;

  /// No description provided for @branchesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load branches: {error}'**
  String branchesLoadFailed(Object error);

  /// No description provided for @gym.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get gym;

  /// No description provided for @addBranch.
  ///
  /// In en, this message translates to:
  /// **'Add branch'**
  String get addBranch;

  /// No description provided for @addGymBranch.
  ///
  /// In en, this message translates to:
  /// **'Add gym branch'**
  String get addGymBranch;

  /// No description provided for @branchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get branchName;

  /// No description provided for @cityOptional.
  ///
  /// In en, this message translates to:
  /// **'City (optional)'**
  String get cityOptional;

  /// No description provided for @branchNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Branch name is required.'**
  String get branchNameRequired;

  /// No description provided for @createBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get createBranch;

  /// No description provided for @memberSignupCode.
  ///
  /// In en, this message translates to:
  /// **'Member signup code'**
  String get memberSignupCode;

  /// No description provided for @signupCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Members enter this code — plus their phone number — to create their own portal account.'**
  String get signupCodeHelp;

  /// No description provided for @noCodeAvailable.
  ///
  /// In en, this message translates to:
  /// **'No code available yet.'**
  String get noCodeAvailable;

  /// No description provided for @gymCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Gym code copied'**
  String get gymCodeCopied;

  /// No description provided for @tapToCopy.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy'**
  String get tapToCopy;

  /// No description provided for @shareWithMembers.
  ///
  /// In en, this message translates to:
  /// **'Share with members'**
  String get shareWithMembers;

  /// No description provided for @attendanceCalendar.
  ///
  /// In en, this message translates to:
  /// **'Attendance calendar'**
  String get attendanceCalendar;

  /// No description provided for @deleteAttendanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete attendance?'**
  String get deleteAttendanceTitle;

  /// No description provided for @permissionToActionDenied.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to {action}.'**
  String permissionToActionDenied(Object action);

  /// No description provided for @noAttendanceRecorded.
  ///
  /// In en, this message translates to:
  /// **'No attendance recorded'**
  String get noAttendanceRecorded;

  /// No description provided for @addAttendance.
  ///
  /// In en, this message translates to:
  /// **'Add attendance'**
  String get addAttendance;

  /// No description provided for @editCorrection.
  ///
  /// In en, this message translates to:
  /// **'Edit correction'**
  String get editCorrection;

  /// No description provided for @searchMember.
  ///
  /// In en, this message translates to:
  /// **'Search member'**
  String get searchMember;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @checkInAt.
  ///
  /// In en, this message translates to:
  /// **'In {time}'**
  String checkInAt(Object time);

  /// No description provided for @manualChangeReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for manual change'**
  String get manualChangeReason;

  /// No description provided for @manualChangeHint.
  ///
  /// In en, this message translates to:
  /// **'Example: biometric device was offline'**
  String get manualChangeHint;

  /// No description provided for @saveAttendance.
  ///
  /// In en, this message translates to:
  /// **'Save attendance'**
  String get saveAttendance;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @presentCount.
  ///
  /// In en, this message translates to:
  /// **'{count} present'**
  String presentCount(Object count);

  /// No description provided for @attendanceEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Choose Add attendance to record a manual correction.'**
  String get attendanceEmptyHint;

  /// No description provided for @correctAttendance.
  ///
  /// In en, this message translates to:
  /// **'Correct attendance'**
  String get correctAttendance;

  /// No description provided for @selectMemberError.
  ///
  /// In en, this message translates to:
  /// **'Select a member.'**
  String get selectMemberError;

  /// No description provided for @clearReasonError.
  ///
  /// In en, this message translates to:
  /// **'Enter a clear reason (at least 5 characters).'**
  String get clearReasonError;

  /// No description provided for @noCheckout.
  ///
  /// In en, this message translates to:
  /// **'No checkout'**
  String get noCheckout;

  /// No description provided for @checkOutAt.
  ///
  /// In en, this message translates to:
  /// **'Out {time}'**
  String checkOutAt(Object time);

  /// No description provided for @enterFiveCharacters.
  ///
  /// In en, this message translates to:
  /// **'Enter at least 5 characters'**
  String get enterFiveCharacters;

  /// No description provided for @leads.
  ///
  /// In en, this message translates to:
  /// **'Leads'**
  String get leads;

  /// No description provided for @followUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get followUp;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @deleteEnquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete enquiry?'**
  String get deleteEnquiryTitle;

  /// No description provided for @deleteEnquiryBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? This cannot be undone.'**
  String deleteEnquiryBody(Object name);

  /// No description provided for @updateStatus.
  ///
  /// In en, this message translates to:
  /// **'Update status'**
  String get updateStatus;

  /// No description provided for @addEnquiry.
  ///
  /// In en, this message translates to:
  /// **'Add enquiry'**
  String get addEnquiry;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @followUpDateOptional.
  ///
  /// In en, this message translates to:
  /// **'Follow-up date (optional)'**
  String get followUpDateOptional;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @saveEnquiry.
  ///
  /// In en, this message translates to:
  /// **'Save enquiry'**
  String get saveEnquiry;

  /// No description provided for @noLeadsYet.
  ///
  /// In en, this message translates to:
  /// **'No leads yet'**
  String get noLeadsYet;

  /// No description provided for @noLeadsYetBody.
  ///
  /// In en, this message translates to:
  /// **'Add the people who walk in or call, and this list tells you who to follow up with each day.'**
  String get noLeadsYetBody;

  /// No description provided for @reminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get reminders;

  /// No description provided for @gymNotFound.
  ///
  /// In en, this message translates to:
  /// **'Gym not found'**
  String get gymNotFound;

  /// No description provided for @push.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get push;

  /// No description provided for @whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsapp;

  /// No description provided for @invoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get invoices;

  /// No description provided for @automaticRenewalNudges.
  ///
  /// In en, this message translates to:
  /// **'Automatic nudges before a membership expires'**
  String get automaticRenewalNudges;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @sendBeforeRenewal.
  ///
  /// In en, this message translates to:
  /// **'SEND BEFORE RENEWAL'**
  String get sendBeforeRenewal;

  /// No description provided for @pushReminders.
  ///
  /// In en, this message translates to:
  /// **'Push reminders'**
  String get pushReminders;

  /// No description provided for @pushReminderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In-app notification to the member'**
  String get pushReminderSubtitle;

  /// No description provided for @reminderWindowsHint.
  ///
  /// In en, this message translates to:
  /// **'Reminders are sent once a day for members whose renewal date matches one of the selected windows.'**
  String get reminderWindowsHint;

  /// No description provided for @whatsappReminders.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp reminders'**
  String get whatsappReminders;

  /// No description provided for @whatsappReminderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Message sent to the member\'s WhatsApp'**
  String get whatsappReminderSubtitle;

  /// No description provided for @oneMessagePerWindow.
  ///
  /// In en, this message translates to:
  /// **'One message per member per window. Each send uses one credit.'**
  String get oneMessagePerWindow;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'MESSAGE'**
  String get message;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'PREVIEW'**
  String get preview;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'CREDITS'**
  String get credits;

  /// No description provided for @sendRemindersNow.
  ///
  /// In en, this message translates to:
  /// **'Send reminders now'**
  String get sendRemindersNow;

  /// No description provided for @invoiceWhatsappMessages.
  ///
  /// In en, this message translates to:
  /// **'Invoice WhatsApp messages'**
  String get invoiceWhatsappMessages;

  /// No description provided for @invoiceWhatsappSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-send invoice and payment receipt to the member'**
  String get invoiceWhatsappSubtitle;

  /// No description provided for @sameWhatsappCredits.
  ///
  /// In en, this message translates to:
  /// **'Uses the same WhatsApp credits as reminders.'**
  String get sameWhatsappCredits;

  /// No description provided for @freeMonthlyQuota.
  ///
  /// In en, this message translates to:
  /// **'Free monthly quota'**
  String get freeMonthlyQuota;

  /// No description provided for @resetsFirstMonth.
  ///
  /// In en, this message translates to:
  /// **'Resets on the 1st of the month'**
  String get resetsFirstMonth;

  /// No description provided for @purchasedCredits.
  ///
  /// In en, this message translates to:
  /// **'Purchased credits'**
  String get purchasedCredits;

  /// No description provided for @staffAndRoles.
  ///
  /// In en, this message translates to:
  /// **'Staff and roles'**
  String get staffAndRoles;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @staffLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load staff. Pull down to retry.'**
  String get staffLoadFailed;

  /// No description provided for @noStaffMembers.
  ///
  /// In en, this message translates to:
  /// **'No staff members yet.'**
  String get noStaffMembers;

  /// No description provided for @inviteStaffMember.
  ///
  /// In en, this message translates to:
  /// **'Invite staff member'**
  String get inviteStaffMember;

  /// No description provided for @removeStaffTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removeStaffTitle(Object name);

  /// No description provided for @removeStaffBody.
  ///
  /// In en, this message translates to:
  /// **'They\'ll lose access to this gym\'s dashboard immediately.'**
  String get removeStaffBody;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @staffMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'Staff member removed'**
  String get staffMemberRemoved;

  /// No description provided for @roles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get roles;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @firstLastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First and last name are required.'**
  String get firstLastNameRequired;

  /// No description provided for @inviteStaff.
  ///
  /// In en, this message translates to:
  /// **'Invite staff'**
  String get inviteStaff;

  /// No description provided for @inviteStaffHelp.
  ///
  /// In en, this message translates to:
  /// **'They\'ll receive an email to set their password and log in.'**
  String get inviteStaffHelp;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @sendingInvite.
  ///
  /// In en, this message translates to:
  /// **'Sending invite…'**
  String get sendingInvite;

  /// No description provided for @sendInvite.
  ///
  /// In en, this message translates to:
  /// **'Send invite'**
  String get sendInvite;

  /// No description provided for @classes.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get classes;

  /// No description provided for @deleteBatch.
  ///
  /// In en, this message translates to:
  /// **'Delete batch'**
  String get deleteBatch;

  /// No description provided for @deleteBatchBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? All sessions and enrollments will also be removed. This cannot be undone.'**
  String deleteBatchBody(Object name);

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String failedToDelete(Object error);

  /// No description provided for @addSession.
  ///
  /// In en, this message translates to:
  /// **'Add session'**
  String get addSession;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @capacityDuration.
  ///
  /// In en, this message translates to:
  /// **'Capacity: {capacity} · {minutes} min'**
  String capacityDuration(Object capacity, Object minutes);

  /// No description provided for @hideSessions.
  ///
  /// In en, this message translates to:
  /// **'Hide sessions'**
  String get hideSessions;

  /// No description provided for @viewSessions.
  ///
  /// In en, this message translates to:
  /// **'View sessions'**
  String get viewSessions;

  /// No description provided for @noUpcomingSessions.
  ///
  /// In en, this message translates to:
  /// **'No upcoming sessions'**
  String get noUpcomingSessions;

  /// No description provided for @noBatchesYet.
  ///
  /// In en, this message translates to:
  /// **'No batches yet'**
  String get noBatchesYet;

  /// No description provided for @addFirstClass.
  ///
  /// In en, this message translates to:
  /// **'Add your first class to get started.'**
  String get addFirstClass;

  /// No description provided for @addBatch.
  ///
  /// In en, this message translates to:
  /// **'Add batch'**
  String get addBatch;

  /// No description provided for @editClass.
  ///
  /// In en, this message translates to:
  /// **'Edit class'**
  String get editClass;

  /// No description provided for @addClass.
  ///
  /// In en, this message translates to:
  /// **'Add class'**
  String get addClass;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @coach.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get coach;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @runsOn.
  ///
  /// In en, this message translates to:
  /// **'Runs on'**
  String get runsOn;

  /// No description provided for @noDaysSelected.
  ///
  /// In en, this message translates to:
  /// **'No days selected — add sessions manually from the calendar.'**
  String get noDaysSelected;

  /// No description provided for @colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colour;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @saveClass.
  ///
  /// In en, this message translates to:
  /// **'Save class'**
  String get saveClass;

  /// No description provided for @removeFromBatch.
  ///
  /// In en, this message translates to:
  /// **'Remove from batch'**
  String get removeFromBatch;

  /// No description provided for @removeMemberFromBatch.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from {batch}?'**
  String removeMemberFromBatch(Object batch, Object name);

  /// No description provided for @searchMembers.
  ///
  /// In en, this message translates to:
  /// **'Search members'**
  String get searchMembers;

  /// No description provided for @allMembersEnrolled.
  ///
  /// In en, this message translates to:
  /// **'All members are already enrolled.'**
  String get allMembersEnrolled;

  /// No description provided for @noMembersFound.
  ///
  /// In en, this message translates to:
  /// **'No members found'**
  String get noMembersFound;

  /// No description provided for @enrolled.
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get enrolled;

  /// No description provided for @noMembersEnrolled.
  ///
  /// In en, this message translates to:
  /// **'No members enrolled yet — add one above.'**
  String get noMembersEnrolled;

  /// No description provided for @paymentsDue.
  ///
  /// In en, this message translates to:
  /// **'Payments due'**
  String get paymentsDue;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get allCaughtUp;

  /// No description provided for @noOverdueUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No overdue or upcoming payments right now.'**
  String get noOverdueUpcoming;

  /// No description provided for @nothingDueThatDay.
  ///
  /// In en, this message translates to:
  /// **'Nothing due that day'**
  String get nothingDueThatDay;

  /// No description provided for @pickAnotherDay.
  ///
  /// In en, this message translates to:
  /// **'Pick another day or clear the filter.'**
  String get pickAnotherDay;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @noOverduePayments.
  ///
  /// In en, this message translates to:
  /// **'No overdue payments'**
  String get noOverduePayments;

  /// No description provided for @everyoneUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Everyone is up to date.'**
  String get everyoneUpToDate;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// No description provided for @nothingDueToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing due today'**
  String get nothingDueToday;

  /// No description provided for @checkComingNext.
  ///
  /// In en, this message translates to:
  /// **'Check what is coming up next.'**
  String get checkComingNext;

  /// No description provided for @nothingComingUp.
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up'**
  String get nothingComingUp;

  /// No description provided for @noPaymentsNext30Days.
  ///
  /// In en, this message translates to:
  /// **'No payments due in the next 30 days.'**
  String get noPaymentsNext30Days;

  /// No description provided for @coming.
  ///
  /// In en, this message translates to:
  /// **'Coming'**
  String get coming;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @showingOneDay.
  ///
  /// In en, this message translates to:
  /// **'Showing one day only'**
  String get showingOneDay;

  /// No description provided for @clearDay.
  ///
  /// In en, this message translates to:
  /// **'Clear day'**
  String get clearDay;

  /// No description provided for @viewExpiredMembers.
  ///
  /// In en, this message translates to:
  /// **'View expired members'**
  String get viewExpiredMembers;

  /// No description provided for @totalOverdue.
  ///
  /// In en, this message translates to:
  /// **'TOTAL OVERDUE'**
  String get totalOverdue;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @initialStatus.
  ///
  /// In en, this message translates to:
  /// **'Initial status'**
  String get initialStatus;

  /// No description provided for @teamMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 team member} other{{count} team members}}'**
  String teamMembersCount(num count);

  /// No description provided for @inviteSentTo.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {email}'**
  String inviteSentTo(Object email);

  /// No description provided for @failedSendInvite.
  ///
  /// In en, this message translates to:
  /// **'Failed to send invite'**
  String get failedSendInvite;

  /// No description provided for @starterStaffLimit.
  ///
  /// In en, this message translates to:
  /// **'Starter includes {count} login. Upgrade to Pro to add staff.'**
  String starterStaffLimit(Object count);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @filterByPlan.
  ///
  /// In en, this message translates to:
  /// **'Filter by plan'**
  String get filterByPlan;

  /// No description provided for @lapsingWithin.
  ///
  /// In en, this message translates to:
  /// **'Lapsing within'**
  String get lapsingWithin;

  /// No description provided for @joinedWithin.
  ///
  /// In en, this message translates to:
  /// **'Joined within'**
  String get joinedWithin;

  /// No description provided for @expiringSoon.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get expiringSoon;

  /// No description provided for @searchMemberHint.
  ///
  /// In en, this message translates to:
  /// **'Name, mobile or member ID'**
  String get searchMemberHint;

  /// No description provided for @stepMember.
  ///
  /// In en, this message translates to:
  /// **'1 · MEMBER'**
  String get stepMember;

  /// No description provided for @stepMembership.
  ///
  /// In en, this message translates to:
  /// **'2 · MEMBERSHIP'**
  String get stepMembership;

  /// No description provided for @stepPayment.
  ///
  /// In en, this message translates to:
  /// **'3 · PAYMENT'**
  String get stepPayment;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get mobileNumber;

  /// No description provided for @batch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get batch;

  /// No description provided for @memberId.
  ///
  /// In en, this message translates to:
  /// **'Member ID'**
  String get memberId;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @amountCollected.
  ///
  /// In en, this message translates to:
  /// **'Amount collected'**
  String get amountCollected;

  /// No description provided for @emergencyContact.
  ///
  /// In en, this message translates to:
  /// **'EMERGENCY CONTACT'**
  String get emergencyContact;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @number.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get number;

  /// No description provided for @emergencyNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Ramesh (father)'**
  String get emergencyNameHint;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @biometricDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Biometric device ID'**
  String get biometricDeviceId;

  /// No description provided for @enrolledBatches.
  ///
  /// In en, this message translates to:
  /// **'Enrolled batches'**
  String get enrolledBatches;

  /// No description provided for @recentCheckIns.
  ///
  /// In en, this message translates to:
  /// **'Recent check-ins'**
  String get recentCheckIns;

  /// No description provided for @recurringDiscount.
  ///
  /// In en, this message translates to:
  /// **'Recurring discount'**
  String get recurringDiscount;

  /// No description provided for @editRecurringDiscountTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring discount'**
  String get editRecurringDiscountTitle;

  /// No description provided for @discountAmount.
  ///
  /// In en, this message translates to:
  /// **'Discount amount'**
  String get discountAmount;

  /// No description provided for @due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get due;

  /// No description provided for @dueTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueTodayLabel;

  /// No description provided for @daysOverdue.
  ///
  /// In en, this message translates to:
  /// **'{days} days overdue'**
  String daysOverdue(Object days);

  /// No description provided for @upcomingInDays.
  ///
  /// In en, this message translates to:
  /// **'Upcoming in {days} days'**
  String upcomingInDays(Object days);

  /// No description provided for @clearDates.
  ///
  /// In en, this message translates to:
  /// **'Clear dates'**
  String get clearDates;

  /// No description provided for @partlyPaid.
  ///
  /// In en, this message translates to:
  /// **'partly paid'**
  String get partlyPaid;

  /// No description provided for @method.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get method;

  /// No description provided for @notesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get notesOptional;

  /// No description provided for @admissionFeeOptional.
  ///
  /// In en, this message translates to:
  /// **'Admission fee (optional)'**
  String get admissionFeeOptional;

  /// No description provided for @discountOptional.
  ///
  /// In en, this message translates to:
  /// **'Discount (optional)'**
  String get discountOptional;

  /// No description provided for @dueDateOptional.
  ///
  /// In en, this message translates to:
  /// **'Due date (optional)'**
  String get dueDateOptional;

  /// No description provided for @deletePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete plan?'**
  String get deletePlanTitle;

  /// No description provided for @planName.
  ///
  /// In en, this message translates to:
  /// **'Plan name'**
  String get planName;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @quarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get quarterly;

  /// No description provided for @sixMonths.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get sixMonths;

  /// No description provided for @yearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearly;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get custom;

  /// No description provided for @durationMonths.
  ///
  /// In en, this message translates to:
  /// **'Duration (months)'**
  String get durationMonths;

  /// No description provided for @maxClassesOptional.
  ///
  /// In en, this message translates to:
  /// **'Max classes (blank = unlimited)'**
  String get maxClassesOptional;

  /// No description provided for @includes.
  ///
  /// In en, this message translates to:
  /// **'Includes'**
  String get includes;

  /// No description provided for @addFeature.
  ///
  /// In en, this message translates to:
  /// **'Add a feature'**
  String get addFeature;

  /// No description provided for @savePlan.
  ///
  /// In en, this message translates to:
  /// **'Save plan'**
  String get savePlan;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language / भाषा'**
  String get language;

  /// No description provided for @tryNewDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'Try the new design?'**
  String get tryNewDesignTitle;

  /// No description provided for @switchBackClassicTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch back to classic?'**
  String get switchBackClassicTitle;

  /// No description provided for @actionSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get actionSwitch;

  /// No description provided for @switchBack.
  ///
  /// In en, this message translates to:
  /// **'Switch back'**
  String get switchBack;

  /// No description provided for @designSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not switch design. Try again.'**
  String get designSwitchFailed;

  /// No description provided for @phoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get phoneOptional;

  /// No description provided for @saveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get saveProfile;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get updatePassword;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @gymName.
  ///
  /// In en, this message translates to:
  /// **'Gym name'**
  String get gymName;

  /// No description provided for @addressOptional.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get addressOptional;

  /// No description provided for @websiteOptional.
  ///
  /// In en, this message translates to:
  /// **'Website URL (optional)'**
  String get websiteOptional;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @saveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save details'**
  String get saveDetails;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @keyId.
  ///
  /// In en, this message translates to:
  /// **'Key ID'**
  String get keyId;

  /// No description provided for @keySecret.
  ///
  /// In en, this message translates to:
  /// **'Key secret'**
  String get keySecret;

  /// No description provided for @enterToUpdate.
  ///
  /// In en, this message translates to:
  /// **'Enter to update'**
  String get enterToUpdate;

  /// No description provided for @updateKeys.
  ///
  /// In en, this message translates to:
  /// **'Update keys'**
  String get updateKeys;

  /// No description provided for @connectRazorpay.
  ///
  /// In en, this message translates to:
  /// **'Connect Razorpay'**
  String get connectRazorpay;

  /// No description provided for @viewPastTickets.
  ///
  /// In en, this message translates to:
  /// **'View past tickets'**
  String get viewPastTickets;

  /// No description provided for @supportTopic.
  ///
  /// In en, this message translates to:
  /// **'What\'s this about?'**
  String get supportTopic;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @shortIssueSummary.
  ///
  /// In en, this message translates to:
  /// **'Short summary of the issue'**
  String get shortIssueSummary;

  /// No description provided for @detailsOptional.
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get detailsOptional;

  /// No description provided for @detailsHint.
  ///
  /// In en, this message translates to:
  /// **'Anything that helps us understand it'**
  String get detailsHint;

  /// No description provided for @submitTicket.
  ///
  /// In en, this message translates to:
  /// **'Submit ticket'**
  String get submitTicket;

  /// No description provided for @myTickets.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get myTickets;

  /// No description provided for @regenerateLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Regenerate link?'**
  String get regenerateLinkTitle;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @selfRegistrationLink.
  ///
  /// In en, this message translates to:
  /// **'Self-registration link'**
  String get selfRegistrationLink;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @regenerateLink.
  ///
  /// In en, this message translates to:
  /// **'Regenerate link'**
  String get regenerateLink;

  /// No description provided for @biometricDevice.
  ///
  /// In en, this message translates to:
  /// **'Biometric device'**
  String get biometricDevice;

  /// No description provided for @pair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pair;

  /// No description provided for @viewSetupGuide.
  ///
  /// In en, this message translates to:
  /// **'View full setup guide'**
  String get viewSetupGuide;

  /// No description provided for @contactWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Contact us on WhatsApp'**
  String get contactWhatsapp;

  /// No description provided for @seeProPlans.
  ///
  /// In en, this message translates to:
  /// **'See Pro plans'**
  String get seeProPlans;

  /// No description provided for @typeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get typeDeleteConfirm;

  /// No description provided for @galleryOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open gallery: {error}'**
  String galleryOpenFailed(Object error);

  /// No description provided for @razorpayConnected.
  ///
  /// In en, this message translates to:
  /// **'Razorpay connected'**
  String get razorpayConnected;

  /// No description provided for @razorpayDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Razorpay disconnected'**
  String get razorpayDisconnected;

  /// No description provided for @ticketsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load tickets: {error}'**
  String ticketsLoadFailed(Object error);

  /// No description provided for @copiedLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String copiedLabel(Object label);

  /// No description provided for @amountRequiredWithCurrency.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency}) *'**
  String amountRequiredWithCurrency(Object currency);

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @gymQr.
  ///
  /// In en, this message translates to:
  /// **'Gym QR'**
  String get gymQr;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkIn;

  /// No description provided for @callTooltip.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callTooltip;

  /// No description provided for @checkoutStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start checkout. Please try again.'**
  String get checkoutStartFailed;

  /// No description provided for @packUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This pack is not available right now.'**
  String get packUnavailable;

  /// No description provided for @purchaseSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Purchase successful — credits will appear shortly.'**
  String get purchaseSuccessful;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed: {error}'**
  String purchaseFailed(Object error);

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send: {error}'**
  String sendFailed(Object error);

  /// No description provided for @className.
  ///
  /// In en, this message translates to:
  /// **'Class name'**
  String get className;

  /// No description provided for @removeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove: {error}'**
  String removeFailed(Object error);

  /// No description provided for @expiring.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get expiring;

  /// No description provided for @joined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get joined;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @onHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get onHold;

  /// No description provided for @statusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get statusNew;

  /// No description provided for @statusContacted.
  ///
  /// In en, this message translates to:
  /// **'Contacted'**
  String get statusContacted;

  /// No description provided for @statusTrial.
  ///
  /// In en, this message translates to:
  /// **'Trial'**
  String get statusTrial;

  /// No description provided for @statusConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get statusConverted;

  /// No description provided for @statusLost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get statusLost;

  /// No description provided for @sourceManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get sourceManual;

  /// No description provided for @sourceWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get sourceWebsite;

  /// No description provided for @sourceReferral.
  ///
  /// In en, this message translates to:
  /// **'Referral'**
  String get sourceReferral;

  /// No description provided for @sourceWalkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get sourceWalkIn;

  /// No description provided for @sourceSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get sourceSocial;

  /// No description provided for @managerAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Members, classes, billing, communications'**
  String get managerAccessHint;

  /// No description provided for @trainerAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Own classes and schedule, check-in, attendance'**
  String get trainerAccessHint;

  /// No description provided for @staffAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Basic access to members and check-ins'**
  String get staffAccessHint;

  /// No description provided for @daysLate.
  ///
  /// In en, this message translates to:
  /// **'{days} days late'**
  String daysLate(Object days);

  /// No description provided for @inDays.
  ///
  /// In en, this message translates to:
  /// **'in {days} days'**
  String inDays(Object days);

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @chooseLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the language you want to use in GymCRM.'**
  String get chooseLanguageSubtitle;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @languageChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can change this later in Settings.'**
  String get languageChangeLater;

  /// No description provided for @welcomeGymcrm.
  ///
  /// In en, this message translates to:
  /// **'Welcome to GymCRM.'**
  String get welcomeGymcrm;

  /// No description provided for @runAGym.
  ///
  /// In en, this message translates to:
  /// **'I run a gym'**
  String get runAGym;

  /// No description provided for @gymMember.
  ///
  /// In en, this message translates to:
  /// **'I\'m a gym member'**
  String get gymMember;

  /// No description provided for @needHelp.
  ///
  /// In en, this message translates to:
  /// **'Need help? '**
  String get needHelp;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get contactUs;

  /// No description provided for @gymTeams.
  ///
  /// In en, this message translates to:
  /// **'FOR GYM TEAMS'**
  String get gymTeams;

  /// No description provided for @runFloorHeadline.
  ///
  /// In en, this message translates to:
  /// **'Run the floor.\nOwn the day.'**
  String get runFloorHeadline;

  /// No description provided for @gymOwner.
  ///
  /// In en, this message translates to:
  /// **'Gym owner'**
  String get gymOwner;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to run today\'s floor.'**
  String get loginSubtitle;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @validEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get validEmail;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @loggingIn.
  ///
  /// In en, this message translates to:
  /// **'Logging in…'**
  String get loggingIn;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get or;

  /// No description provided for @newGym.
  ///
  /// In en, this message translates to:
  /// **'New gym? '**
  String get newGym;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAccount;

  /// No description provided for @secureRecovery.
  ///
  /// In en, this message translates to:
  /// **'SECURE RECOVERY'**
  String get secureRecovery;

  /// No description provided for @recoveryHeadline.
  ///
  /// In en, this message translates to:
  /// **'Back in.\nNo stress.'**
  String get recoveryHeadline;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the email you signed up with. We will send a reset link.'**
  String get resetPasswordHelp;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @checkYourEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'CHECK YOUR EMAIL'**
  String get checkYourEmailLabel;

  /// No description provided for @resetHeadline.
  ///
  /// In en, this message translates to:
  /// **'One tap\nto reset.'**
  String get resetHeadline;

  /// No description provided for @linkSent.
  ///
  /// In en, this message translates to:
  /// **'Link sent'**
  String get linkSent;

  /// No description provided for @checkEmailPrefix.
  ///
  /// In en, this message translates to:
  /// **'Check '**
  String get checkEmailPrefix;

  /// No description provided for @resetLinkExpiry.
  ///
  /// In en, this message translates to:
  /// **' and open the reset link. It expires in one hour.'**
  String get resetLinkExpiry;

  /// No description provided for @checkSpam.
  ///
  /// In en, this message translates to:
  /// **'Not in your inbox? Check spam'**
  String get checkSpam;

  /// No description provided for @sendAgainIn.
  ///
  /// In en, this message translates to:
  /// **', or send it again in {seconds}s.'**
  String sendAgainIn(Object seconds);

  /// No description provided for @sendAgain.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get sendAgain;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to log in'**
  String get backToLogin;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'← Back'**
  String get back;

  /// No description provided for @buildWithGymcrm.
  ///
  /// In en, this message translates to:
  /// **'BUILD WITH GYMCRM'**
  String get buildWithGymcrm;

  /// No description provided for @gymOnePlace.
  ///
  /// In en, this message translates to:
  /// **'Your gym.\nOne place.'**
  String get gymOnePlace;

  /// No description provided for @createYourGym.
  ///
  /// In en, this message translates to:
  /// **'Create your gym'**
  String get createYourGym;

  /// No description provided for @oneMinute.
  ///
  /// In en, this message translates to:
  /// **'Takes about a minute.'**
  String get oneMinute;

  /// No description provided for @signupGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Google'**
  String get signupGoogle;

  /// No description provided for @gymNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Gym name is required'**
  String get gymNameRequired;

  /// No description provided for @countryCurrency.
  ///
  /// In en, this message translates to:
  /// **'Country and currency'**
  String get countryCurrency;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @mobileOptional.
  ///
  /// In en, this message translates to:
  /// **'Mobile number (optional)'**
  String get mobileOptional;

  /// No description provided for @validMobile.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number'**
  String get validMobile;

  /// No description provided for @tapFlagCountry.
  ///
  /// In en, this message translates to:
  /// **'Tap the flag to change country'**
  String get tapFlagCountry;

  /// No description provided for @minEightCharacters.
  ///
  /// In en, this message translates to:
  /// **'Min. 8 characters'**
  String get minEightCharacters;

  /// No description provided for @passwordEightCharacters.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordEightCharacters;

  /// No description provided for @alreadyGymcrm.
  ///
  /// In en, this message translates to:
  /// **'Already on GymCRM? '**
  String get alreadyGymcrm;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'← Change email'**
  String get changeEmail;

  /// No description provided for @verifyEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'VERIFY YOUR EMAIL'**
  String get verifyEmailLabel;

  /// No description provided for @almostThere.
  ///
  /// In en, this message translates to:
  /// **'Almost there.'**
  String get almostThere;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkYourEmail;

  /// No description provided for @sentSixDigitCode.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to\n'**
  String get sentSixDigitCode;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @resendCodeIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String resendCodeIn(Object seconds);

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @codeResentEmail.
  ///
  /// In en, this message translates to:
  /// **'Code resent — check your email.'**
  String get codeResentEmail;

  /// No description provided for @weak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get weak;

  /// No description provided for @fair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get fair;

  /// No description provided for @strong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strong;

  /// No description provided for @agreeTo.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get agreeTo;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get and;

  /// No description provided for @acceptTermsError.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms of Service and Privacy Policy to continue.'**
  String get acceptTermsError;

  /// No description provided for @continueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueGoogle;

  /// No description provided for @mobileAccess.
  ///
  /// In en, this message translates to:
  /// **'MOBILE ACCESS'**
  String get mobileAccess;

  /// No description provided for @mobileAccessHeadline.
  ///
  /// In en, this message translates to:
  /// **'One code.\nYou are in.'**
  String get mobileAccessHeadline;

  /// No description provided for @loginWithMobile.
  ///
  /// In en, this message translates to:
  /// **'Log in with mobile'**
  String get loginWithMobile;

  /// No description provided for @mobileOtpHelp.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a one-time code.'**
  String get mobileOtpHelp;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @otpSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send OTP. Please try again.'**
  String get otpSendFailed;

  /// No description provided for @codeResentSms.
  ///
  /// In en, this message translates to:
  /// **'Code resent via SMS.'**
  String get codeResentSms;

  /// No description provided for @resendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not resend code. Please try again.'**
  String get resendFailed;

  /// No description provided for @incorrectCode.
  ///
  /// In en, this message translates to:
  /// **'Incorrect code. Please try again.'**
  String get incorrectCode;

  /// No description provided for @verificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed. Please try again.'**
  String get verificationFailed;

  /// No description provided for @verifyYourNumber.
  ///
  /// In en, this message translates to:
  /// **'VERIFY YOUR NUMBER'**
  String get verifyYourNumber;

  /// No description provided for @checkMessages.
  ///
  /// In en, this message translates to:
  /// **'Check your messages.'**
  String get checkMessages;

  /// No description provided for @enterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Enter verification code'**
  String get enterVerificationCode;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @setUpYourGym.
  ///
  /// In en, this message translates to:
  /// **'Set up your gym'**
  String get setUpYourGym;

  /// No description provided for @setupStep.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 4'**
  String setupStep(int step);

  /// No description provided for @tellUsAboutGym.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your gym'**
  String get tellUsAboutGym;

  /// No description provided for @membersWillSee.
  ///
  /// In en, this message translates to:
  /// **'This is what members will see.'**
  String get membersWillSee;

  /// No description provided for @createGym.
  ///
  /// In en, this message translates to:
  /// **'Create Gym'**
  String get createGym;

  /// No description provided for @freeTrialNoCard.
  ///
  /// In en, this message translates to:
  /// **'3-day free trial · No credit card needed'**
  String get freeTrialNoCard;

  /// No description provided for @optionalLabel.
  ///
  /// In en, this message translates to:
  /// **'— optional'**
  String get optionalLabel;

  /// No description provided for @monthlyMembership.
  ///
  /// In en, this message translates to:
  /// **'Monthly membership'**
  String get monthlyMembership;

  /// No description provided for @planNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Plan name is required.'**
  String get planNameRequired;

  /// No description provided for @planPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a price for this plan.'**
  String get planPriceRequired;

  /// No description provided for @planCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the plan. Please try again.'**
  String get planCreateFailed;

  /// No description provided for @createFirstPlan.
  ///
  /// In en, this message translates to:
  /// **'Create your first membership plan'**
  String get createFirstPlan;

  /// No description provided for @createFirstPlanHelp.
  ///
  /// In en, this message translates to:
  /// **'Set the plan your members will join.'**
  String get createFirstPlanHelp;

  /// No description provided for @billingCycle.
  ///
  /// In en, this message translates to:
  /// **'Billing cycle'**
  String get billingCycle;

  /// No description provided for @whatsIncluded.
  ///
  /// In en, this message translates to:
  /// **'What\'s included'**
  String get whatsIncluded;

  /// No description provided for @createPlanContinue.
  ///
  /// In en, this message translates to:
  /// **'Create plan & continue'**
  String get createPlanContinue;

  /// No description provided for @creatingPlan.
  ///
  /// In en, this message translates to:
  /// **'Creating plan…'**
  String get creatingPlan;

  /// No description provided for @firstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required.'**
  String get firstNameRequired;

  /// No description provided for @memberAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add this member. Please try again.'**
  String get memberAddFailed;

  /// No description provided for @addFirstMember.
  ///
  /// In en, this message translates to:
  /// **'Add your first member'**
  String get addFirstMember;

  /// No description provided for @addFirstMemberHelp.
  ///
  /// In en, this message translates to:
  /// **'You can add more members anytime.'**
  String get addFirstMemberHelp;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get plan;

  /// No description provided for @moreMemberDetails.
  ///
  /// In en, this message translates to:
  /// **'More details — member ID, amount paid, notes'**
  String get moreMemberDetails;

  /// No description provided for @amountPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get amountPaid;

  /// No description provided for @notesHint.
  ///
  /// In en, this message translates to:
  /// **'Anything to remember'**
  String get notesHint;

  /// No description provided for @addingMember.
  ///
  /// In en, this message translates to:
  /// **'Adding member…'**
  String get addingMember;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNow;

  /// No description provided for @yourGym.
  ///
  /// In en, this message translates to:
  /// **'Your gym'**
  String get yourGym;

  /// No description provided for @gymReady.
  ///
  /// In en, this message translates to:
  /// **'Your gym is ready'**
  String get gymReady;

  /// No description provided for @gymCreated.
  ///
  /// In en, this message translates to:
  /// **'Gym created'**
  String get gymCreated;

  /// No description provided for @firstPlanCreated.
  ///
  /// In en, this message translates to:
  /// **'First plan created'**
  String get firstPlanCreated;

  /// No description provided for @firstMemberAdded.
  ///
  /// In en, this message translates to:
  /// **'First member added'**
  String get firstMemberAdded;

  /// No description provided for @goToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Go to dashboard'**
  String get goToDashboard;

  /// No description provided for @setupReadyHelp.
  ///
  /// In en, this message translates to:
  /// **'You can add more plans, members and staff from the dashboard.'**
  String get setupReadyHelp;

  /// No description provided for @addMenuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What do you want to add?'**
  String get addMenuSubtitle;

  /// No description provided for @addMenuMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get addMenuMember;

  /// No description provided for @addMenuMemberHint.
  ///
  /// In en, this message translates to:
  /// **'New joining, plan and first payment'**
  String get addMenuMemberHint;

  /// No description provided for @addMenuInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get addMenuInvoice;

  /// No description provided for @addMenuInvoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Bill a member for a plan or service'**
  String get addMenuInvoiceHint;

  /// No description provided for @addMenuPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get addMenuPlan;

  /// No description provided for @addMenuPlanHint.
  ///
  /// In en, this message translates to:
  /// **'Monthly, quarterly or yearly membership'**
  String get addMenuPlanHint;

  /// No description provided for @addMenuLead.
  ///
  /// In en, this message translates to:
  /// **'Lead'**
  String get addMenuLead;

  /// No description provided for @addMenuLeadHint.
  ///
  /// In en, this message translates to:
  /// **'Walk-in or enquiry to follow up'**
  String get addMenuLeadHint;

  /// No description provided for @addMenuBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get addMenuBatch;

  /// No description provided for @addMenuBatchHint.
  ///
  /// In en, this message translates to:
  /// **'Morning, evening or a class with fixed timing'**
  String get addMenuBatchHint;

  /// No description provided for @addMenuStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get addMenuStaff;

  /// No description provided for @addMenuStaffHint.
  ///
  /// In en, this message translates to:
  /// **'Invite a trainer, manager or front desk'**
  String get addMenuStaffHint;

  /// No description provided for @addMenuExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get addMenuExpense;

  /// No description provided for @addMenuExpenseHint.
  ///
  /// In en, this message translates to:
  /// **'Rent, salary, equipment, utilities'**
  String get addMenuExpenseHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
