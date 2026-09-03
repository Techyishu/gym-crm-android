import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// New-feature entries only — bug fixes don't go here. Newest first.
class WhatsNewEntry {
  final String version;
  final String date;
  final String title;
  final List<String> bullets;
  const WhatsNewEntry({
    required this.version,
    required this.date,
    required this.title,
    required this.bullets,
  });
}

const whatsNewEntries = <WhatsNewEntry>[
  WhatsNewEntry(
    version: '1.0.4+1',
    date: '2 Sep 2026',
    title: 'Members can reset their own password',
    bullets: [
      'A member who forgets their portal password can now reset it themselves — Forgot password? on the member login, then gym code, mobile number, the code we text them, and a new password.',
      'Nothing for you to do at the desk: no re-invite, no account deletion.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.3+50',
    date: '30 Aug 2026',
    title: 'GST on invoices, and downloads you can find',
    bullets: [
      'Invoices now print the GST breakup — taxable value, CGST and SGST — along with your GSTIN, whenever GST is switched on. Until now these only appeared in the shared PDF, never on the invoice you look at in the app.',
      'GST rate and the GST breakup switch sit together in Invoice settings, and warn you when only one of them is set — a rate on its own was silently adding no tax at all.',
      'Saving an invoice PDF or a data export now asks where to put it, so the file lands in your Downloads instead of a private app folder you could not open.',
      'Backing out of an export no longer records it as completed, and keeps your filters so you can try again.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.3+1',
    date: '27 Aug 2026',
    title: 'A calmer, clearer app',
    bullets: [
      'Home now opens with "Needs attention" — overdue payments, memberships about to lapse, leads past their follow-up date and check-ins still waiting to sync — above the day\'s numbers.',
      'Billing is now called Money, and its top card splits what you still have to collect from what you have already collected this month.',
      'The members list shows a Collect button straight on the card of anyone who owes you money.',
      'Check-in puts the scanner and manual search together in one panel, with today\'s arrivals below it.',
      'The member app\'s bottom bar now has a tab for every section and a raised button for your QR code.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.2+46',
    date: '23 Aug 2026',
    title: 'Multiple gym branches',
    bullets: [
      'Owners can now add more than one gym branch to a single account and switch between them — each branch keeps its own members, billing, check-ins, staff and reports.',
      'Switch or add a branch from More → Gym Branches.',
      'WhatsApp, Razorpay and biometric devices are set up per branch — a new branch starts with these disconnected until you configure them for it.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.2+46',
    date: '22 Aug 2026',
    title: 'Biometric attendance (beta)',
    bullets: [
      'Connect an eSSL/ZKTeco fingerprint device so members check in automatically — no manual entry, no shared QR code.',
      'Set up from More → Biometric Device — pair your device by serial number, then add each member\'s Biometric ID from their profile.',
      'Beta: works end-to-end in testing, still being validated against real hardware. Contact us if your device behaves differently.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.2+46',
    date: '20 Aug 2026',
    title: 'Delete invoices (owner)',
    bullets: [
      'Gym owners can now delete a wrong invoice from the invoice detail screen or by long-pressing it in the Billing feed.',
      'Deleting an invoice also removes any payments recorded against it — this cannot be undone.',
    ],
  ),
  WhatsNewEntry(
    version: '1.0.1+45',
    date: '11 Aug 2026',
    title: 'Member self-serve signup',
    bullets: [
      'Members can create their own portal account: enter your gym\'s code + phone number, verify with a one-time code, set a password.',
      'Share your gym code from the dashboard — tap the code to copy, or use the share button.',
      'Member portal: Bookings tab replaced with a Check-in tab (QR scan/show).',
    ],
  ),
];

void showWhatsNewSheet(BuildContext context) {
  showAdaptiveSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "What's new",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: whatsNewEntries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (_, i) {
                  final entry = whatsNewEntries[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.date,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkHint,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...entry.bullets.map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '•  ',
                                style: TextStyle(
                                  color: AppTheme.inkSoft,
                                  fontSize: 13,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  b,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.inkSoft,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
