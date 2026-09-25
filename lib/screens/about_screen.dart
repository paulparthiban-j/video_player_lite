import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF2A2A2A) : Colors.grey[300]!;
    final primaryText = colorScheme.onSurface;
    final secondaryText = colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'About',
          style: TextStyle(color: primaryText, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryText),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),

            // App Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.play_circle_outline,
                size: 60,
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 24),

            // App Name
            Text(
              'PARTHI PLAY',
              style: TextStyle(
                color: primaryText,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Version
            Text(
              'Version 1.0.0',
              style: TextStyle(color: secondaryText, fontSize: 16),
            ),

            const SizedBox(height: 8),

            // Build Number
            Text(
              'Build 20240101',
              style: TextStyle(color: secondaryText, fontSize: 14),
            ),

            const SizedBox(height: 32),

            // Description
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Parthi Play is a professional video player application designed for the best viewing experience. With support for multiple video formats, gesture controls, and advanced features, it provides everything you need for video playback.',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Features
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Key Features',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    context,
                    '- Support for multiple video formats',
                  ),
                  _buildFeatureItem(
                    context,
                    '- Gesture controls for easy navigation',
                  ),
                  _buildFeatureItem(context, '- Adjustable playback speed'),
                  _buildFeatureItem(context, '- Multiple aspect ratio options'),
                  _buildFeatureItem(context, '- Subtitle support'),
                  _buildFeatureItem(context, '- Hardware acceleration'),
                  _buildFeatureItem(context, '- Performance optimization'),
                  _buildFeatureItem(context, '- Dark theme interface'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Developer Info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Developer',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Professional Flutter Development',
                    style: TextStyle(color: primaryText, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Built with Flutter and Riverpod',
                    style: TextStyle(color: secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Contact & Links
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLinkItem(
                    context,
                    'Report Issues',
                    Icons.bug_report,
                    () => _launchUrl('https://github.com/issues'),
                  ),
                  _buildLinkItem(
                    context,
                    'Request Features',
                    Icons.lightbulb_outline,
                    () => _launchUrl('https://github.com/features'),
                  ),
                  _buildLinkItem(
                    context,
                    'Rate App',
                    Icons.star,
                    () => _launchUrl('https://play.google.com/store'),
                  ),
                  _buildLinkItem(
                    context,
                    'Share App',
                    Icons.share,
                    () => _shareApp(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Legal
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Legal',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLinkItem(
                    context,
                    'Privacy Policy',
                    Icons.privacy_tip,
                    () => _showPrivacyPolicy(context),
                  ),
                  _buildLinkItem(
                    context,
                    'Terms of Service',
                    Icons.description,
                    () => _showTermsOfService(context),
                  ),
                  _buildLinkItem(
                    context,
                    'Licenses',
                    Icons.info,
                    () => _showLicenses(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Copyright
            Text(
              '© 2024 Parthi Play',
              style: TextStyle(color: secondaryText, fontSize: 12),
            ),

            const SizedBox(height: 8),

            Text(
              'All rights reserved',
              style: TextStyle(color: secondaryText, fontSize: 12),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      ),
    );
  }

  Widget _buildLinkItem(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: Colors.red, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              color: colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    const shareText =
        'Check out Parthi Play — a powerful video player with advanced features.';
    const subject = 'Parthi Play';

    unawaited(
      Share.share(shareText, subject: subject).catchError((e) {
        debugPrint('Error sharing app: $e');
        if (!context.mounted) return ShareResult.unavailable;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open share sheet'),
            backgroundColor: Colors.red,
          ),
        );
        return ShareResult.unavailable;
      }),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Privacy Policy',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: SingleChildScrollView(
          child: Text(
            'Privacy Policy for Parthi Play\n\n'
            'Last updated: January 1, 2024\n\n'
            'This privacy policy explains how Parthi Play collects, uses, and protects your information.\n\n'
            'Information We Collect:\n'
            '- Usage analytics and crash reports\n'
            '- Device information for optimization\n'
            '- User preferences and settings\n\n'
            'How We Use Information:\n'
            '- To improve app performance and features\n'
            '- To fix bugs and crashes\n'
            '- To provide customer support\n\n'
            'Data Protection:\n'
            '- All data is stored locally on your device\n'
            '- No personal information is shared with third parties\n'
            '- We use industry-standard security measures\n\n'
            'Contact Us:\n'
            'If you have questions about this privacy policy, please contact us.',
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showTermsOfService(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Terms of Service',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: SingleChildScrollView(
          child: Text(
            'Terms of Service for Parthi Play\n\n'
            'Last updated: January 1, 2024\n\n'
            'By using Parthi Play, you agree to these terms:\n\n'
            '1. Acceptance of Terms\n'
            'By using this app, you accept these terms and conditions.\n\n'
            '2. Use of the App\n'
            '- You may use this app for personal, non-commercial purposes\n'
            '- You must not reverse engineer or modify the app\n'
            '- You must not violate any applicable laws\n\n'
            '3. Intellectual Property\n'
            'All content and features are owned by Parthi Play or its licensors.\n\n'
            '4. Disclaimer\n'
            'The app is provided "as is" without warranties of any kind.\n\n'
            '5. Limitation of Liability\n'
            'Parthi Play is not liable for any damages arising from app use.\n\n'
            '6. Changes to Terms\n'
            'We reserve the right to modify these terms at any time.\n\n'
            '7. Contact Information\n'
            'For questions about these terms, please contact us.',
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'PARTHI PLAY',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.play_circle_outline, color: Colors.red),
      applicationLegalese: '© 2024 Parthi Play. All rights reserved.',
    );
  }
}
