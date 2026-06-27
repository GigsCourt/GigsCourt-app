import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeScaleAnimation;
  bool _isEarlyAccess = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();

    // Fetch Remote Config before navigating
    _loadRemoteConfig();
  }

  Future<void> _loadRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.fetchAndActivate();
      _isEarlyAccess = !remoteConfig.getBool('subscriptions_enforced');
    } catch (e) {
      // Default to Early Access if Remote Config fails
      _isEarlyAccess = true;
    }

    // Wait for animation to complete before navigating
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _navigateToNext();
      }
    });
  }

  void _navigateToNext() async {
    final user = FirebaseAuth.instance.currentUser;

    // ========== 1. NO USER → WIZARD ==========
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/wizard');
      }
      return;
    }

    // ========== 2. VALIDATE TOKEN ==========
    try {
      await user.getIdToken(true);
    } catch (e) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/wizard');
      }
      return;
    }

    // ========== 3. EMAIL NOT VERIFIED → VERIFY EMAIL ==========
    if (!user.emailVerified) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/verify-email');
      }
      return;
    }

    // ========== 4. CHECK SETUP COMPLETION ==========
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        // User document doesn't exist → go to setup
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/setup');
        }
        return;
      }

      final isSetupComplete = doc.data()?['isSetupComplete'] ?? false;

      if (!isSetupComplete) {
        // Setup not completed → go to setup
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/setup');
        }
        return;
      }

      // ========== 5. ALL CHECKS PASSED → HOME ==========
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }

    } catch (e) {
      // Error fetching user document → go to setup (safest fallback)
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/setup');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: Center(
        child: FadeTransition(
          opacity: _fadeScaleAnimation,
          child: ScaleTransition(
            scale: _fadeScaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'GigsCourt',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 36,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your Service, Your Court',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 16,
                    color: Colors.white.withAlpha(204),
                    letterSpacing: 0.5,
                  ),
                ),
                if (_isEarlyAccess) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🚀 Early Access',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}