import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  String? _photoUrl;
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();
  LatLng? _location;
  List<Map<String, dynamic>> _selectedServices = [];
  bool _isSaving = false;

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

  bool get _canProceedFromCurrentStep {
    switch (_currentStep) {
      case 0:
        return _photoUrl != null;
      case 1:
        return _name.isNotEmpty && _bio.isNotEmpty;
      case 2:
        return _location != null && _address.trim().isNotEmpty;
      case 3:
        return _selectedServices.isNotEmpty;
      case 4:
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
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': _name,
        'bio': _bio,
        'photoUrl': _photoUrl,
        'email': user.email,
        'isSetupComplete': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('providers').doc(user.uid).set({
        'services': _selectedServices.map((s) => s['id']).toList(),
        'workPhotos': [],
        'subscriptionStatus': 'free',
        'leadCount': 0,
        'reviewCount': 0,
        'averageRating': 0.0,
        'lastReviewedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await Supabase.instance.client.rpc('upsert_provider_location', params: {
        'p_user_id': user.uid,
        'p_latitude': _location!.latitude,
        'p_longitude': _location!.longitude,
        'p_address': _address,
      });

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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: _dismissKeyboard,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_currentStep > 0)
                          GestureDetector(
                            onTap: _goToPreviousStep,
                            child: Icon(Icons.arrow_back,
                                color: AppColors.textPrimary, size: 24),
                          ),
                        const Spacer(),
                        Text(
                          'Step ${_currentStep + 1} of $_totalSteps',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    ),
                    StepAddress(
                      addressController: _addressController,
                      onAddressChanged: (location, address) {
                        setState(() {
                          _location = location;
                        });
                      },
                    ),
                    StepServices(
                      onServicesChanged: (services) {
                        setState(() {
                          _selectedServices = services;
                        });
                      },
                    ),
                    const StepHowItWorks(),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
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
                        ? const SizedBox(
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
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
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