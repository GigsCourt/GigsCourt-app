import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../theme/app_theme.dart';

class WizardScreen extends StatefulWidget {
  const WizardScreen({super.key});

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _WizardScreenState extends State<WizardScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isEarlyAccess = false;

  final List<WizardSlide> _slides = [
    WizardSlide(
      iconPath: 'assets/icons/compass.svg',
      headline: 'Find Services Around You',
      body:
          'Discover trusted barbers, plumbers, tailors and more \u2014 right in your neighborhood.',
    ),
    WizardSlide(
      iconPath: 'assets/icons/chat_circle_dots.svg',
      headline: 'Chat & Connect',
      body:
          'Message providers anytime. Discuss details, negotiate prices, and stay updated \u2014 all in one place.',
    ),
    WizardSlide(
      iconPath: 'assets/icons/wallet.svg',
      headline: 'Earn on GigsCourt',
      body:
          "You\u2019re not just a client. List your skills, build your reputation, and earn. Your service, your court.",
    ),
  ];

  // ========== RESPONSIVE HELPERS ==========

  double _getFontSize(double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return baseSize * 0.85;
    if (screenWidth > 600) return baseSize * 1.1;
    return baseSize;
  }

  double _getPadding(double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return basePadding * 0.7;
    if (screenWidth > 600) return basePadding * 1.2;
    return basePadding;
  }

  double _getIconSize() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return 70;
    if (screenWidth > 600) return 120;
    return 100;
  }

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !FirebaseRemoteConfig.instance.getBool('subscriptions_enforced');
  }

  void _goToNextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/signup');
    }
  }

  void _goToSignUp() {
    Navigator.of(context).pushReplacementNamed('/signup');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(16.0);
    final padding = _getPadding(40.0);
    final iconSize = _getIconSize();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _goToSignUp,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: fontSize,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildSlide(_slides[index], fontSize, padding, iconSize);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: _currentPage == index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.primary
                          : AppColors.primary.withAlpha(51),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            if (_isEarlyAccess)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Free during Early Access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: fontSize - 3,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _goToNextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(WizardSlide slide, double fontSize, double padding, double iconSize) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            slide.iconPath,
            height: iconSize,
            width: iconSize,
            colorFilter: const ColorFilter.mode(
              AppColors.primary,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(height: fontSize * 3),
          Text(
            slide.headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: fontSize + 8,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          SizedBox(height: fontSize),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              fontSize: fontSize,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class WizardSlide {
  final String iconPath;
  final String headline;
  final String body;

  WizardSlide({
    required this.iconPath,
    required this.headline,
    required this.body,
  });
}