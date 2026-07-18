# App Store Connect — iOS listing copy + rejection reply

## Promotional Text (170 char max, editable anytime without a new build)

GymCRM helps you run your gym end to end — memberships, QR check-ins, billing, staff roles, and reports, all from your phone.

(158 chars)

---

## Description (no char limit shown in ASC, keep first 3 lines strong — that's what shows above "more")

Run your entire gym from your phone. GymCRM is the all-in-one management app for gym owners, managers, and trainers — memberships, check-ins, billing, and communication in one place.

MEMBERSHIP MANAGEMENT
• Add, edit, and track members with photos, plans, and payment status
• Automatic plan expiry tracking with renewal reminders
• Bulk import members via CSV

QR CHECK-INS
• Members check in with a QR code — no manual attendance logs
• Works offline and syncs automatically when back online
• Live check-in feed for staff

BILLING & PAYMENTS
• Track dues, payments, and outstanding balances per member
• Earnings and revenue reports at a glance
• Upcoming payment reminders so nothing slips through

STAFF & ROLES
• Owner, manager, trainer, and staff roles with permission-based access
• Multiple staff logins per gym
• Role-based dashboards

MEMBER PORTAL
• Members get their own self-service portal
• View plan status, payment history, and QR check-in code
• Class schedules and bookings

LEADS & CRM
• Track leads from first contact to conversion
• Follow-up reminders so no lead goes cold

REPORTS & ANALYTICS
• Revenue, attendance, and membership trend reports
• Understand your gym's growth at a glance

SUBSCRIPTION
GymCRM Pro unlocks unlimited members, unlimited staff logins, advanced reports, class scheduling, and WhatsApp due reminders. Subscriptions are billed monthly or annually and purchased securely through the App Store. Manage or cancel anytime from your Apple ID settings.

Built for gym owners who want less paperwork and more time on the floor.

---

## What's New (this version)

• Subscribe directly through the App Store — no external checkout
• Faster check-in flow with offline support
• Bug fixes and performance improvements

---

## Reply to App Review (paste into the same thread in App Store Connect)

Thank you for the detailed feedback. We've addressed all three items:

**Guideline 3.1.1 / 3.1.2 (In-App Purchase)**
The app has been updated so that on iOS, GymCRM Pro is purchased exclusively through the In-App Purchase API (StoreKit, via RevenueCat). We removed every non-IAP purchasing path from the iOS build — there is no external checkout link, web redirect, or other purchase mechanism reachable from iOS. Users are directed only to the native App Store purchase sheet.

**Guideline 2.1(b) (Free trial removed / purchase flow)**
We removed the free trial entirely from the iOS app. New iOS sign-ups now go straight from account creation to the paywall and must complete an In-App Purchase before they can use the app — there is no trial period, grace window, or alternate access path on iOS. (Android retains a locally-offered trial; that is a separate, non-iOS build and unrelated to this submission.)

Purchase flow once a user has no active subscription:
1. User signs up / logs in.
2. App checks subscription status via RevenueCat/StoreKit entitlements.
3. If there is no active entitlement, the app shows a paywall listing the available subscription packages (monthly/annual) with live App Store pricing.
4. Tapping a plan calls `Purchases.purchasePackage()`, which opens the native StoreKit purchase sheet.
5. On successful purchase, the RevenueCat entitlement updates and the app unlocks automatically — no manual step, no separate login, no external site.
6. A "Restore purchases" option is available on the same screen for users switching devices or reinstalling.

Demo account with an expired/no subscription, provided in the App Review Information section:
Username: [ADD DEMO EMAIL]
Password: [ADD DEMO PASSWORD]

This account has no active plan, so on login it will show the paywall directly, letting you verify the purchase flow end to end.

**Guideline 2.3.10 (Screenshots — non-iOS status bar)**
We will replace all screenshots with new captures taken directly from iOS Simulator/device on the supported target devices, so the status bar, home indicator, and chrome are all native iOS. Updated screenshots will be uploaded via Media Manager before resubmission.

Please let us know if you need anything further to complete the review.
