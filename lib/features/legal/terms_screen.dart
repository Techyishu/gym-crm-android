import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_info.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _webUrl = 'https://gymcrm.in/terms';

  Future<void> _openWeb() async {
    final uri = Uri.parse(_webUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Terms of Service'),
        actions: [
          TextButton(onPressed: _openWeb, child: const Text('View on Web')),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: _TermsContent(),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _UpdatedChip(date: 'Last updated: 2 July 2026'),
        const SizedBox(height: 16),
        const _Heading('Terms of Service — GymCRM'),
        const _Body(
          'Please read these Terms of Service ("Terms") carefully before using GymCRM. '
          'By creating an account or using the app, you agree to be bound by these Terms.',
        ),
        const SizedBox(height: 20),
        const _Section(
          title: '1. The Service',
          body:
              'GymCRM is a gym management platform that allows gym owners and staff to manage memberships, '
              'billing, classes, check-ins, and communications. GymCRM is operated by Shashank Kumar, India.',
        ),
        const _Section(
          title: '2. Account Registration',
          body:
              'You must be at least 18 years old to create an account. You are responsible for maintaining '
              'the security of your account credentials and for all activity that occurs under your account. '
              'Notify us immediately at shashanksingh67567@gmail.com if you suspect unauthorised access.',
        ),
        _Section(
          title: '3. Subscriptions',
          body: isIOS
              ? 'GymCRM requires an active subscription from sign-up — there is no free trial on iOS. '
                    'Subscription plans and pricing are shown in the app and purchased via the App Store.\n\n'
                    'Subscriptions are billed monthly or annually as chosen. You may cancel at any time via your '
                    'Apple ID subscription settings; cancellation takes effect at the end of the current billing '
                    'period. No refunds are issued for unused periods.'
              : 'New gym-owner accounts receive a 3-day free trial with full access. After the trial, '
                    'continued use requires an active subscription. Subscription plans and pricing are listed at gymcrm.in.\n\n'
                    'Subscriptions are billed monthly or annually as chosen. You may cancel at any time; '
                    'cancellation takes effect at the end of the current billing period. No refunds are issued for unused periods.',
        ),
        _Section(
          title: '4. Subscription Management',
          body: isIOS
              ? 'Subscriptions are purchased and managed through the App Store using your Apple ID. '
                    'Use the "Manage subscription" option in Settings to view billing, cancel, or restore purchases.'
              : 'Subscriptions are managed at gymcrm.in. Tap "Open gymcrm.in" to visit the website '
                    'where you can start or manage your plan. Your subscription status applies automatically '
                    'across all your devices.',
        ),
        _Section(
          title: '5. Acceptable Use',
          body:
              'GymCRM is intended exclusively for legitimate fitness businesses (gyms, fitness centres, personal training studios, and similar). '
              'By using GymCRM you confirm that your business is a genuine fitness or wellness operation.\n\n'
              'You agree not to:\n'
              '• Use GymCRM for any unlawful, fraudulent, or deceptive purpose.\n'
              '• Register a gym account to manage contacts who are not actual members or clients of a real fitness business.\n'
              '• Use the communication features to send unsolicited messages, spam, or content unrelated to your members\' fitness services.\n'
              '• Misrepresent your business type, name, or purpose to obtain access to the platform.\n'
              '• Use member data stored in GymCRM for any purpose other than managing your legitimate gym operations.\n'
              '• Upload malware, spam, or abusive content.\n'
              '• Reverse engineer, decompile, or attempt to extract source code from the app.\n'
              '• Resell or sublicense access to GymCRM without written permission.\n\n'
              'We reserve the right to investigate suspicious activity and terminate accounts that we reasonably believe are operating outside a legitimate fitness business context, without prior notice.',
        ),
        _Section(
          title: '6. Your Data',
          body:
              'You retain ownership of all data you enter into GymCRM (gym details, member records, etc.). '
              'You grant us a limited licence to store and process that data solely to provide the service. '
              'See our Privacy Policy for full details on data handling.',
        ),
        _Section(
          title: '7. Service Availability',
          body:
              'We aim for high availability but do not guarantee uninterrupted service. '
              'We may perform maintenance, upgrades, or changes at any time. '
              'We are not liable for losses resulting from downtime.',
        ),
        _Section(
          title: '8. Limitation of Liability',
          body:
              'To the maximum extent permitted by law, GymCRM and its operators are not liable for '
              'indirect, incidental, special, or consequential damages arising from your use of the service. '
              'Our total liability to you will not exceed the amount you paid in the 3 months preceding the claim.',
        ),
        _Section(
          title: '9. Termination',
          body:
              'We may suspend or terminate your account if you violate these Terms or engage in conduct '
              'that harms the service or other users. You may delete your account at any time from '
              'Settings → Delete Account in the app, or by contacting shashanksingh67567@gmail.com.',
        ),
        _Section(
          title: '10. Governing Law',
          body:
              'These Terms are governed by the laws of India. Any disputes will be subject to the exclusive '
              'jurisdiction of the courts of India.',
        ),
        _Section(
          title: '11. Changes to Terms',
          body:
              'We may update these Terms from time to time. We will notify you of material changes via the app '
              'or by email. Continued use after changes constitutes acceptance of the updated Terms.',
        ),
        _Section(
          title: '12. Contact',
          body:
              'GymCRM — Operated by Shashank Kumar\nEmail: shashanksingh67567@gmail.com\nWhatsApp: +91 75410 04076\nWebsite: gymcrm.in',
        ),
      ],
    );
  }
}

class _UpdatedChip extends StatelessWidget {
  final String date;
  const _UpdatedChip({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.activeBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        date,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppTheme.ink,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: AppTheme.textSecondary,
        height: 1.6,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
