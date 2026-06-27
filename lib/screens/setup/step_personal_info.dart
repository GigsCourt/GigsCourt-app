import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class StepPersonalInfo extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController bioController;
  final bool isBioOptional;

  const StepPersonalInfo({
    super.key,
    required this.nameController,
    required this.bioController,
    this.isBioOptional = false,
  });

  // ========== RESPONSIVE HELPERS ==========

  double _getFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return baseSize * 0.85;
    if (screenWidth > 600) return baseSize * 1.1;
    return baseSize;
  }

  double _getPadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return basePadding * 0.8;
    if (screenWidth > 600) return basePadding * 1.2;
    return basePadding;
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(context, 16.0);
    final padding = _getPadding(context, 32.0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: fontSize + 8,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps clients know who you are and what you do.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: fontSize,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(fontSize: fontSize),
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'Enter your full name',
              labelStyle: TextStyle(fontSize: fontSize),
              hintStyle: TextStyle(fontSize: fontSize),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: fontSize + 4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: bioController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: fontSize),
            decoration: InputDecoration(
              labelText: isBioOptional ? 'Bio (Optional)' : 'Bio',
              hintText: isBioOptional
                  ? 'Tell clients about yourself (optional, but recommended for more leads)'
                  : 'Tell clients a bit about yourself...',
              labelStyle: TextStyle(fontSize: fontSize),
              hintStyle: TextStyle(fontSize: fontSize),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: fontSize + 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}