import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/imagekit_service.dart';

class StepPhoto extends StatefulWidget {
  final Function(String?) onPhotoUploaded;

  const StepPhoto({super.key, required this.onPhotoUploaded});

  @override
  State<StepPhoto> createState() => _StepPhotoState();
}

class _StepPhotoState extends State<StepPhoto> {
  File? _selectedPhoto;
  bool _isUploading = false;
  String? _uploadedUrl;
  String? _errorMessage;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked == null) return;

    setState(() {
      _selectedPhoto = File(picked.path);
      _isUploading = true;
      _errorMessage = null;
    });

    final url = await ImageKitService.uploadImage(
      _selectedPhoto!,
      'profile_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (mounted) {
      setState(() {
        _isUploading = false;
        if (url != null) {
          _uploadedUrl = url;
          _errorMessage = null;
        } else {
          _errorMessage = 'Upload failed. Check your connection and try again.';
        }
      });
      widget.onPhotoUploaded(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Add a profile photo',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This helps clients recognize you',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _isUploading ? null : _pickAndUpload,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _errorMessage != null
                      ? AppColors.error.withAlpha(20)
                      : AppColors.primary.withAlpha(20),
                  border: Border.all(
                    color: _uploadedUrl != null
                        ? AppColors.success
                        : _errorMessage != null
                            ? AppColors.error
                            : AppColors.primary.withAlpha(51),
                    width: _uploadedUrl != null ? 3 : 2,
                  ),
                  image: _selectedPhoto != null
                      ? DecorationImage(
                          image: FileImage(_selectedPhoto!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _isUploading
                    ? const CircularProgressIndicator(color: AppColors.primary)
                    : _uploadedUrl != null
                        ? const Icon(Icons.check, color: AppColors.success, size: 48)
                        : _errorMessage != null
                            ? const Icon(Icons.error_outline, color: AppColors.error, size: 48)
                            : const Icon(
                                Icons.camera_alt_outlined,
                                size: 48,
                                color: AppColors.primary,
                              ),
              ),
            ),
            if (_uploadedUrl != null) ...[
              const SizedBox(height: 16),
              Text(
                'Photo uploaded successfully',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.success,
                  fontSize: 14,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.error,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}