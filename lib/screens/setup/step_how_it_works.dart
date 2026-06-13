import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class StepHowItWorks extends StatelessWidget {
  const StepHowItWorks({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'How GigsCourt Works',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 40),
          _buildInfoCard(
            Icons.visibility_outlined,
            'Visibility',
            'Your profile appears to clients near you based on your skills and location.',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            Icons.star_outline,
            'Reputation',
            'As clients engage with you, your reviews and active status grow.',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            Icons.card_giftcard_outlined,
            'Free Access',
            'Full visibility at no cost until you reach 20 leads or 5 reviews.',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            Icons.verified_outlined,
            'GigsCourt Premium',
            'Unlimited visibility, verified badge, and priority ranking.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}