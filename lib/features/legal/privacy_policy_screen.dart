import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _webUrl = 'https://gymcrm.in/privacy';

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
        title: const Text('Privacy Policy'),
        actions: [
          TextButton(
            onPressed: _openWeb,
            child: const Text('View on Web'),
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: _PolicyContent(),
      ),
    );
  }
}

class _PolicyContent extends StatelessWidget {
  const _PolicyContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _UpdatedChip(date: 'Last updated: 23 June 2026'),
        SizedBox(height: 16),
        _Heading('Privacy Policy — GymCRM'),
        _Body(
          'GymCRM ("we", "our", or "us") is a gym management platform operated by Shashank Kumar. '
          'This policy explains how we collect, use, and protect information when you use our mobile app and website (gymcrm.in).',
        ),
        SizedBox(height: 20),
        _Section(
          title: '1. Information We Collect',
          body:
              'Account information: name, email address, and mobile number when you create an account.\n\n'
              'Gym data: gym name, address, member records (name, phone, gender, membership plans, attendance, payments, notes, workout plans), '
              'billing history, class schedules, and documents that you enter into the app.\n\n'
              'Device & usage data: IP address, device type, OS version, and in-app activity logs used to improve performance and diagnose issues. '
              'Error reports and stack traces are sent to Sentry (US) for crash diagnosis. '
              'Usage patterns are tracked via PostHog analytics (US).\n\n'
              'Login monitoring: when you log in, the gym name and timestamp are sent to an internal monitoring channel for operational health purposes.\n\n'
              'Camera & photos: with your permission, to scan QR codes for member check-in and to upload profile photos. '
              'Member photos are stored in a private storage bucket and are never publicly accessible.',
        ),
        _Section(
          title: '2. How We Use Your Information',
          body:
              '• Provide and operate the GymCRM service.\n'
              '• Send transactional emails (account verification, password reset, renewal reminders) via Resend (US).\n'
              '• Send WhatsApp notifications for membership renewals via the Meta WhatsApp Business API (US).\n'
              '• Process subscription payments via Dodo Payments or Razorpay (India).\n'
              '• Monitor platform health and detect unusual account activity.\n'
              '• Improve the app through anonymised analytics.\n'
              '• Respond to support requests.',
        ),
        _Section(
          title: '3. Data Storage & Security',
          body:
              'Your data is stored on Supabase infrastructure (PostgreSQL hosted on AWS). All data is encrypted in transit (TLS) and at rest. '
              'Row-Level Security (RLS) ensures each gym can only access its own data — no gym can see another gym\'s members or records. '
              'We follow industry-standard security practices to protect your information.',
        ),
        _Section(
          title: '4. Third-Party Services',
          body:
              'We use the following services to operate GymCRM:\n\n'
              '• Supabase (AWS, Ireland) — database, authentication, file storage.\n'
              '• Vercel (US) — web hosting.\n'
              '• Sentry (US) — error monitoring and crash reports.\n'
              '• PostHog (US) — product analytics.\n'
              '• Resend (US) — transactional email.\n'
              '• Razorpay (India) — payment processing.\n'
              '• Dodo Payments — subscription billing.\n'
              '• Meta WhatsApp Business API (US) — WhatsApp notifications.\n'
              '• Telegram — internal operational alerts (gym login timestamps only; no member data).\n\n'
              'We do not sell or rent your data to any third party.',
        ),
        _Section(
          title: '5. Member Data (Gym Owners)',
          body:
              'Gym owners who add member records to GymCRM are the Data Fiduciaries for that member data under the DPDP Act 2023. '
              'GymCRM acts as a Data Processor. Gym owners are responsible for:\n\n'
              '• Obtaining appropriate consent from their members before entering data into GymCRM.\n'
              '• Informing members that their data is managed via a third-party platform.\n'
              '• Complying with DPDP Act 2023 obligations for member data.\n'
              '• Obtaining member consent before enabling WhatsApp reminders.',
        ),
        _Section(
          title: '6. Android App Permissions',
          body:
              'CAMERA — scans QR codes and captures member profile photos.\n\n'
              'READ/WRITE_EXTERNAL_STORAGE — selects photos from gallery and saves exported reports.\n\n'
              'INTERNET — syncs data with the GymCRM cloud backend.\n\n'
              'You can revoke any permission at any time via Android Settings → Apps → GymCRM → Permissions.',
        ),
        _Section(
          title: '7. Data Retention',
          body:
              'Active accounts: data is retained while your account is active.\n\n'
              'After cancellation: data is retained for 30 days to allow export, then permanently deleted.\n\n'
              'Billing records: retained for up to 8 years as required by Indian tax law.\n\n'
              'Deleted data may persist in encrypted backups for up to 7 days.',
        ),
        _Section(
          title: '8. Your Rights (DPDP Act 2023)',
          body:
              'Under India\'s Digital Personal Data Protection Act 2023, you have the right to:\n\n'
              '• Access — request a copy of your personal data.\n'
              '• Correction — ask us to correct inaccurate data.\n'
              '• Erasure — request deletion of your data (subject to legal retention obligations).\n'
              '• Data portability — export your data as CSV from account settings.\n'
              '• Grievance redressal — raise a complaint with our Grievance Officer.\n'
              '• Nominate — nominate someone to exercise your rights on your behalf.\n\n'
              'Contact us at shashanksingh67567@gmail.com. We will respond within 30 days.',
        ),
        _Section(
          title: '9. Children',
          body:
              'GymCRM is intended for business owners and their adult members. '
              'Gym owners who enroll members under 18 must obtain parental or guardian consent before entering their data. '
              'Contact us if you believe a minor\'s data has been submitted without consent and we will delete it.',
        ),
        _Section(
          title: '10. Changes to This Policy',
          body:
              'We may update this policy periodically. We will notify you of material changes via the app or email. '
              'Continued use after changes constitutes acceptance.',
        ),
        _Section(
          title: '11. Grievance Officer & Contact',
          body:
              'Grievance Officer: Shashank Kumar\n'
              'Email: shashanksingh67567@gmail.com\n'
              'WhatsApp: +91 75410 04076\n'
              'Website: gymcrm.in\n'
              'Response time: within 72 hours on business days',
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
      child: Text(date,
          style: const TextStyle(
              fontSize: 12, color: AppTheme.ink, fontWeight: FontWeight.w500)),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.ink));
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 14, color: AppTheme.textSecondary, height: 1.6));
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
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}
