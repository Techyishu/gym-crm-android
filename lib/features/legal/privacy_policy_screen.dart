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
        _UpdatedChip(date: 'Last updated: June 2025'),
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
              'Gym data: gym name, address, member records, billing history, and class schedules that you enter into the app.\n\n'
              'Device & usage data: IP address, device type, OS version, and in-app activity logs used to improve performance and diagnose issues.\n\n'
              'Camera & photos: with your permission, to scan QR codes for member check-in and to upload profile photos. We do not store images on our servers beyond your explicit uploads.',
        ),
        _Section(
          title: '2. How We Use Your Information',
          body:
              '• Provide and operate the GymCRM service.\n'
              '• Send transactional emails (account verification, password reset).\n'
              '• Process subscription payments via DodoPayments (Android) or your bank via our website.\n'
              '• Improve the app through anonymised analytics.\n'
              '• Respond to support requests.',
        ),
        _Section(
          title: '3. Data Storage & Security',
          body:
              'Your data is stored on Supabase infrastructure (PostgreSQL hosted on AWS). All data is encrypted in transit (TLS) and at rest. '
              'We follow industry-standard security practices to protect your information.',
        ),
        _Section(
          title: '4. Sharing of Information',
          body:
              'We do not sell or rent your personal data. We share data only with:\n\n'
              '• Supabase Inc. — database and authentication infrastructure.\n'
              '• DodoPayments / Razorpay — payment processing (Android/web only); we share only what is necessary to complete transactions.\n\n'
              'We may disclose information if required by law or to protect our legal rights.',
        ),
        _Section(
          title: '5. Member Data (Gym Owners)',
          body:
              'Gym owners who add member records to GymCRM are data controllers for that member data. '
              'GymCRM acts as a data processor. Gym owners are responsible for obtaining appropriate consent from their members and complying with applicable data protection laws.',
        ),
        _Section(
          title: '6. Data Retention',
          body:
              'We retain your account data for as long as your account is active. '
              'If you delete your account, your personal data is removed within 30 days, except where retention is required by law.',
        ),
        _Section(
          title: '7. Your Rights',
          body:
              'You may request access to, correction of, or deletion of your personal data by contacting us at support@gymcrm.in. '
              'We will respond within 30 days.',
        ),
        _Section(
          title: '8. Children',
          body:
              'GymCRM is intended for use by business owners and their adult members. We do not knowingly collect data from children under 13.',
        ),
        _Section(
          title: '9. Changes to This Policy',
          body:
              'We may update this policy periodically. We will notify you of material changes via the app or email. '
              'Continued use after changes constitutes acceptance.',
        ),
        _Section(
          title: '10. Contact',
          body:
              'GymCRM\nEmail: support@gymcrm.in\nWebsite: gymcrm.in',
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
