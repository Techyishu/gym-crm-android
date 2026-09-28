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
