import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class StepPersonalInfo extends StatefulWidget {
  final Function(String name, String bio) onInfoChanged;

  const StepPersonalInfo({super.key, required this.onInfoChanged});

  @override
  State<StepPersonalInfo> createState() => _StepPersonalInfoState();
}

class _StepPersonalInfoState extends State<StepPersonalInfo> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_notifyParent);
    _bioController.addListener(_notifyParent);
  }

  void _notifyParent() {
    widget.onInfoChanged(
      _nameController.text.trim(),
      _bioController.text.trim(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps clients know who you are and what you do.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'Enter your full name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Bio',
              hintText: 'Tell clients a bit about yourself...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}