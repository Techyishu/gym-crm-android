import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// New-feature entries only — bug fixes don't go here. Newest first.
class WhatsNewEntry {
  final String version;
  final String date;
  final String title;
  final List<String> bullets;
  const WhatsNewEntry({required this.version, required this.date, required this.title, required this.bullets});
}

const whatsNewEntries = <WhatsNewEntry>[
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
                child: Text("What's new", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
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
                      Text(entry.date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkHint)),
                      const SizedBox(height: 4),
                      Text(entry.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                      const SizedBox(height: 8),
                      ...entry.bullets.map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  ', style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
                                Expanded(child: Text(b, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4))),
                              ],
                            ),
                          )),
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
