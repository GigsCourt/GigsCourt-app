import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import 'setup/step_photo.dart';
import 'setup/step_personal_info.dart';
import 'setup/step_address.dart';
import 'setup/step_skills.dart';
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

  // Collected data from each step
  String? _photoUrl;
  String _name = '';
  String _bio = '';
  LatLng? _location;
  String _address = '';
  List<Map<String, dynamic>> _selectedSkills = [];
  bool _isSaving = false;

  // Validation
  bool get _canProceedFromCurrentStep {
    switch (_currentStep) {
      case 0:
        return _photoUrl != null;
      case 1:
        return _name.trim().isNotEmpty && _bio.trim().isNotEmpty;
      case 2:
        return _location != null && _address.trim().isNotEmpty;
      case 3:
        return _selectedSkills.isNotEmpty;
      case 4:
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
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

      // Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': _name,
        'bio': _bio,
        'photoUrl': _photoUrl,
        'email': user.email,
        'isSetupComplete': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save location to Supabase
      await Supabase.instance.client.from('provider_locations').upsert({
        'user_id': user.uid,
        'latitude': _location!.latitude,
        'longitude': _location!.longitude,
        'address': _address,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Save skills to Supabase
      for (final skill in _selectedSkills) {
        await Supabase.instance.client.rpc('add_user_skill', params: {
          'p_user_id': user.uid,
          'p_skill_id': skill['id'],
        });
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
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

            // Steps
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  StepPhoto(
                    onPhotoUploaded: (url) {
                      _photoUrl = url;
                    },
                  ),
                  StepPersonalInfo(
                    onInfoChanged: (name, bio) {
                      _name = name;
                      _bio = bio;
                    },
                  ),
                  StepAddress(
                    onAddressChanged: (location, address) {
                      _location = location;
                      _address = address;
                    },
                  ),
                  StepSkills(
                    onSkillsChanged: (skills) {
                      _selectedSkills = skills;
                    },
                  ),
                  const StepHowItWorks(),
                ],
              ),
            ),

            // Bottom button
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
    );
  }
}