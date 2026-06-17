import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'setup/step_photo.dart';
import 'setup/step_personal_info.dart';
import 'setup/step_services.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();
  String? _photoUrl;
  List<Map<String, dynamic>> _selectedServices = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final providerDoc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();

    final userData = userDoc.data();
    final providerData = providerDoc.data();

    _nameController.text = userData?['displayName'] ?? '';
    _bioController.text = userData?['bio'] ?? '';
    _photoUrl = userData?['photoUrl'];

    final serviceIds = List<int>.from(providerData?['services'] ?? []);
    if (serviceIds.isNotEmpty) {
      final namesData = await Supabase.instance.client.rpc('get_service_names', params: {
        'service_ids': serviceIds,
      });
      _selectedServices = List<Map<String, dynamic>>.from(namesData);
    }

    setState(() {});
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'displayName': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        if (_photoUrl != null) 'photoUrl': _photoUrl,
      });

      await FirebaseFirestore.instance.collection('providers').doc(user.uid).update({
        'services': _selectedServices.map((s) => s['id']).toList(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Edit Profile',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            StepPhoto(
              onPhotoUploaded: (url) => _photoUrl = url,
              existingUrl: _photoUrl,
            ),
            const SizedBox(height: 24),
            StepPersonalInfo(
              nameController: _nameController,
              bioController: _bioController,
            ),
            const SizedBox(height: 24),
            StepServices(
              onServicesChanged: (services) => _selectedServices = services,
            ),
          ],
        ),
      ),
    );
  }
}