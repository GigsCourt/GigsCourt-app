import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';
import 'setup/step_photo.dart';
import 'setup/step_personal_info.dart';
import 'setup/step_address.dart';
import 'setup/step_services.dart';
import 'setup/step_how_it_works.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 5;

  final List<String> _stepTitles = [
    'Profile Photo',
    'Personal Info',
    'Address',
    'Select Services',
    'How It Works',
  ];

  String? _photoUrl;
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();
  LatLng? _location;
  List<Map<String, dynamic>> _selectedServices = [];
  bool _isSaving = false;

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

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_updateAddress);
  }

  void _updateAddress() {
    _address = _addressController.text;
  }

  String get _name => _nameController.text.trim();
  String get _bio => _bioController.text.trim();
  String _address = '';

  // ========== VALIDATION ==========

  bool get _canProceedFromCurrentStep {
    switch (_currentStep) {
      case 0: // Profile Photo — REQUIRED
        return _photoUrl != null;
      case 1: // Personal Info — Name REQUIRED, Bio OPTIONAL
        return _name.isNotEmpty;
      case 2: // Address — OPTIONAL
        return true;
      case 3: // Services — OPTIONAL
        return true;
      case 4: // How It Works — INFO ONLY
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _goToNextStep() {
    _dismissKeyboard();

    if (!_canProceedFromCurrentStep) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete this step before continuing.')),
      );
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeSetup();
    }
  }

  void _goToPreviousStep() {
    _dismissKeyboard();
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/wizard');
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // Build user data
      final Map<String, dynamic> userData = {
        'displayName': _name,
        'photoUrl': _photoUrl,
        'email': user.email,
        'isSetupComplete': true,
        'workPhotos': [],
        'subscriptionStatus': 'free',
        'leadCount': 0,
        'reviewCount': 0,
        'averageRating': 0.0,
        'lastReviewedAt': null,
        'pushNotifications': true,
        'emailNotifications': true,
        'isOnline': false,
        'lastSeen': null,
        'phone': null,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Only add bio if provided
      if (_bio.isNotEmpty) {
        userData['bio'] = _bio;
      }

      // Only add services if selected
      if (_selectedServices.isNotEmpty) {
        userData['services'] = _selectedServices.map((s) => s['id']).toList();
      } else {
        userData['services'] = [];
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData);

      // Only save address if provided
      if (_location != null && _address.trim().isNotEmpty) {
        await Supabase.instance.client.rpc('upsert_provider_location', params: {
          'p_user_id': user.uid,
          'p_latitude': _location!.latitude,
          'p_longitude': _location!.longitude,
          'p_address': _address,
        });
      }

      // Only save services if selected
      for (final service in _selectedServices) {
        await Supabase.instance.client.rpc('add_user_service', params: {
          'p_user_id': user.uid,
          'p_service_id': service['id'],
        });
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save your profile. Please check your connection and try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(14.0);
    final padding = _getPadding(24.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: _dismissKeyboard,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _goToPreviousStep,
                          child: Icon(
                            Icons.arrow_back,
                            color: AppColors.textPrimary,
                            size: fontSize + 10,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Step ${_currentStep + 1} of $_totalSteps',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            fontSize: fontSize,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stepTitles[_currentStep],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: fontSize + 6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentStep + 1) / _totalSteps,
                        backgroundColor: AppColors.primary.withAlpha(26),
                        color: AppColors.primary,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    _dismissKeyboard();
                    setState(() => _currentStep = index);
                  },
                  children: [
                    StepPhoto(
                      onPhotoUploaded: (url) {
                        setState(() => _photoUrl = url);
                      },
                      existingUrl: _photoUrl,
                    ),
                    StepPersonalInfo(
                      nameController: _nameController,
                      bioController: _bioController,
                      isBioOptional: true,
                    ),
                    StepAddress(
                      addressController: _addressController,
                      onAddressChanged: (location, address) {
                        setState(() {
                          _location = location;
                        });
                      },
                      isOptional: true,
                    ),
                    StepServices(
                      onServicesChanged: (services) {
                        setState(() {
                          _selectedServices = services;
                        });
                      },
                      isOptional: true,
                    ),
                    const StepHowItWorks(),
                  ],
                ),
              ),

              Padding(
                padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _goToNextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _currentStep == _totalSteps - 1
                                ? 'Get Started'
                                : 'Continue',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: fontSize + 2,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}