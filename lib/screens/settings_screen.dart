import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isEarlyAccess = false;
  bool _pushNotifications = true;
  bool _emailNotifications = true;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !FirebaseRemoteConfig.instance.getBool('subscriptions_enforced');
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      setState(() {
        _pushNotifications = doc.data()?['pushNotifications'] ?? true;
        _emailNotifications = doc.data()?['emailNotifications'] ?? true;
      });
    }
  }

  Future<void> _saveNotificationSetting(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({key: value});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Settings',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Account'),
          _buildTile(Icons.person_outline, 'Edit Profile', onTap: () {
            Navigator.of(context).pushNamed('/edit-profile');
          }),
          _buildTile(Icons.email_outlined, 'Email', subtitle: user?.email ?? ''),
          _buildTile(Icons.lock_outline, 'Change Password', onTap: () async {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password reset email sent.')),
              );
            }
          }),
          const SizedBox(height: 20),
          _buildSection('Notifications'),
          _buildSwitchTile('Push Notifications', _pushNotifications, (val) {
            setState(() => _pushNotifications = val);
            _saveNotificationSetting('pushNotifications', val);
          }),
          _buildSwitchTile('Email Notifications', _emailNotifications, (val) {
            setState(() => _emailNotifications = val);
            _saveNotificationSetting('emailNotifications', val);
          }),
          const SizedBox(height: 20),
          _buildSection('About'),
          _buildTile(Icons.description_outlined, 'Privacy Policy', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _buildLegalScreen('Privacy Policy', _privacyPolicy),
            ));
          }),
          _buildTile(Icons.article_outlined, 'Terms of Service', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _buildLegalScreen('Terms of Service', _termsOfService),
            ));
          }),
          if (_isEarlyAccess)
            _buildTile(Icons.info_outline, 'About Early Access', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _buildLegalScreen('Early Access', _earlyAccessInfo),
              ));
            }),
          _buildTile(Icons.info_outline, 'App Version', subtitle: '1.0.0'),
          const SizedBox(height: 20),
          _buildTile(Icons.support_outlined, 'Help & Support', onTap: () {
            Navigator.of(context).pushNamed('/support');
          }),
          const SizedBox(height: 20),
          _buildTile(Icons.logout, 'Log Out', onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/splash', (route) => false);
            }
          }),
          const SizedBox(height: 12),
          _buildTile(Icons.delete_outline, 'Delete Account', color: AppColors.error, onTap: () {
            _showDeleteDialog(context);
          }),
        ],
      ),
    );
  }

  Widget _buildLegalScreen(String title, String content) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(content, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.textPrimary, height: 1.6)),
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textSecondary)),
    );
  }

  Widget _buildTile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: color ?? AppColors.textPrimary)),
                if (subtitle != null) Text(subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500)),
        const Spacer(),
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
      ]),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Account', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        content: const Text('Your account will be deactivated for 30 days and then permanently deleted.', style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                await Supabase.instance.client.rpc('remove_user_data', params: {'p_user_id': user.uid});
                await user.delete();
              }
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/splash', (route) => false);
              }
            },
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  static const String _privacyPolicy = '''
Privacy Policy

Last updated: June 2026

GigsCourt ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and share your information when you use our app.

Information We Collect
- Account information: email address, display name, profile photo
- Location data: workspace address for provider discovery
- Usage data: app interactions, features used
- Communication data: messages sent through the app

How We Use Your Information
- To provide and improve our services
- To connect clients with nearby service providers
- To send notifications about messages, reviews, and account updates
- To ensure platform safety and prevent fraud

Data Sharing
- Your profile information is visible to other users as described in the app
- We do not sell your personal data to third parties
- We may share data with service providers (hosting, analytics) to operate the app

Data Security
We implement appropriate security measures to protect your data. However, no method of electronic storage is 100% secure.

Contact Us
For privacy-related inquiries, contact us at support@gigscourt.com
''';

  static const String _termsOfService = '''
Terms of Service

Last updated: June 2026

By using GigsCourt, you agree to these terms.

1. Account Registration
You must provide accurate information when creating an account. You are responsible for maintaining the confidentiality of your login credentials.

2. Provider Subscriptions
Providers may be required to subscribe for continued visibility after reaching certain engagement thresholds. Subscription fees are non-refundable unless required by law.

3. User Conduct
You agree not to:
- Post false or misleading information
- Harass or abuse other users
- Use the platform for illegal activities
- Attempt to bypass subscription requirements

4. Content
You retain ownership of content you post. By posting, you grant us a license to display it within the app.

5. Limitation of Liability
GigsCourt is a discovery platform. We are not responsible for the quality of services provided by users or any disputes between users.

6. Termination
We may suspend or terminate accounts that violate these terms.

Contact: support@gigscourt.com
''';

  static const String _earlyAccessInfo = '''
About Early Access

GigsCourt is currently in Early Access. During this period, all features are free for all users.

What This Means
- Full visibility for all providers at no cost
- Unlimited client leads
- All features unlocked

What Happens Later
When the platform reaches sufficient activity, a subscription model will be introduced. Providers will be notified well in advance.

Subscription will be required for:
- Continued visibility after reaching engagement milestones
- Verified badge and priority ranking

Clients will always be free.

Pricing will be announced before subscriptions go live. Thank you for being an early supporter of GigsCourt!
''';
}