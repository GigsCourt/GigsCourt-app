import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isResending = false;

  // ========== RESPONSIVE HELPERS ==========

  double _getFontSize(double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return baseSize * 0.85;
    if (screenWidth > 600) return baseSize * 1.1;
    return baseSize;
  }

  double _getPadding(double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return basePadding * 0.8;
    if (screenWidth > 600) return basePadding * 1.2;
    return basePadding;
  }

  // ========== AUTH FUNCTIONS ==========

  Future<void> _checkEmailVerified() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final isVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (mounted) {
      if (isVerified) {
        Navigator.of(context).pushReplacementNamed('/setup');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Email not verified yet. Please check your inbox and click the verification link.'),
          ),
        );
      }
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    await FirebaseAuth.instance.currentUser?.sendEmailVerification();
    if (mounted) {
      setState(() => _isResending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email resent.')),
      );
    }
  }

  Future<void> _wrongEmail() async {
    await FirebaseAuth.instance.currentUser?.delete();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/signup');
    }
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(16.0);
    final padding = _getPadding(32.0);
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.email_outlined,
                  size: 80,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Verify Your Email',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize + 8,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'We sent a verification link to\n$email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: fontSize,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _checkEmailVerified,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'I\'ve Verified My Email',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: fontSize,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isResending ? null : _resendEmail,
                  child: _isResending
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          'Resend Email',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            fontSize: fontSize - 2,
                            color: AppColors.primary,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _wrongEmail,
                  child: Text(
                    'Wrong email? Go back',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: fontSize - 2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}