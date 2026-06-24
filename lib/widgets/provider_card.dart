import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

class ProviderCard extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool isVerified;
  final bool isOnline;
  final String? lastSeen;
  final List<String> services;
  final double rating;
  final int reviewCount;
  final double distanceKm;
  final bool isHorizontal;
  final VoidCallback onTap;
  final bool isLocked; // ← NEW: Lock state indicator

  const ProviderCard({
    super.key,
    required this.name,
    this.photoUrl,
    required this.isVerified,
    required this.isOnline,
    this.lastSeen,
    required this.services,
    required this.rating,
    required this.reviewCount,
    required this.distanceKm,
    this.isHorizontal = false,
    required this.onTap,
    this.isLocked = false, // ← NEW
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isHorizontal ? 280 : null,
        margin: const EdgeInsets.only(right: 12, bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: isHorizontal ? _buildHorizontalCard() : _buildVerticalCard(context),
      ),
    );
  }

  Widget _buildHorizontalCard() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: photoUrl != null
                      ? Image.network(photoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.primary.withAlpha(26),
                          child: Icon(Icons.person, color: AppColors.primary),
                        ),
                ),
              ),
              // ========== LOCK OVERLAY ==========
              if (isLocked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    SvgPicture.asset(
                      'assets/icons/verified.svg',
                      width: 14,
                      height: 14,
                      colorFilter: const ColorFilter.mode(
                        AppColors.accent,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                  // ========== PREMIUM BADGE ==========
                  if (isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Premium',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                _buildStatusRow(),
                const SizedBox(height: 3),
                Text(
                  services.take(2).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  SvgPicture.asset(
                    'assets/icons/star.svg',
                    width: 12,
                    height: 12,
                    colorFilter: const ColorFilter.mode(
                      AppColors.accent,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$rating ($reviewCount)',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SvgPicture.asset(
                    'assets/icons/map_pin.svg',
                    width: 12,
                    height: 12,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      '${distanceKm.toStringAsFixed(1)} km',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalCard(BuildContext context) {
    // Get screen width for responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final isLargeScreen = screenWidth > 500;

    // Responsive font sizes
    final nameSize = isSmallScreen ? 12.0 : (isLargeScreen ? 14.0 : 13.0);
    final labelSize = isSmallScreen ? 10.0 : (isLargeScreen ? 12.0 : 11.0);
    final statusSize = isSmallScreen ? 10.0 : (isLargeScreen ? 12.0 : 11.0);
    final buttonSize = isSmallScreen ? 11.0 : (isLargeScreen ? 13.0 : 12.0);

    // Responsive spacing
    final verticalSpacing = isSmallScreen ? 2.0 : 3.0;
    final paddingHorizontal = isSmallScreen ? 8.0 : 10.0;
    final paddingVertical = isSmallScreen ? 6.0 : 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Image - fixed height 120px
        Stack(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: photoUrl != null
                    ? Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.primary.withAlpha(26),
                            child: Icon(
                              Icons.person,
                              color: AppColors.primary,
                              size: 36,
                            ),
                          );
                        },
                      )
                    : Container(
                        color: AppColors.primary.withAlpha(26),
                        child: Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 36,
                        ),
                      ),
              ),
            ),
            // ========== LOCK OVERLAY ==========
            if (isLocked)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_outline,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            // ========== PREMIUM BADGE ==========
            if (isVerified)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(26),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/verified.svg',
                        width: 12,
                        height: 12,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Premium',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // Content area
        Padding(
          padding: EdgeInsets.fromLTRB(
            paddingHorizontal,
            paddingVertical,
            paddingHorizontal,
            paddingVertical,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Line 1: Name + Verified badge
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: nameSize,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    SvgPicture.asset(
                      'assets/icons/verified.svg',
                      width: nameSize + 1,
                      height: nameSize + 1,
                      colorFilter: const ColorFilter.mode(
                        AppColors.accent,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                ],
              ),
              // Line 2: Status (Online / Last seen)
              Padding(
                padding: EdgeInsets.only(top: verticalSpacing),
                child: _buildStatusRow(statusSize),
              ),
              // Line 3: Services (ALL in ONE line with truncation)
              Padding(
                padding: EdgeInsets.only(top: verticalSpacing),
                child: Text(
                  services.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: labelSize,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // Line 4: Rating + Reviews
              Padding(
                padding: EdgeInsets.only(top: verticalSpacing),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/star.svg',
                      width: labelSize,
                      height: labelSize,
                      colorFilter: const ColorFilter.mode(
                        AppColors.accent,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$rating ($reviewCount)',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: labelSize,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Line 5: Distance
              Padding(
                padding: EdgeInsets.only(top: verticalSpacing),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/map_pin.svg',
                      width: labelSize,
                      height: labelSize,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km away',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: labelSize,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Line 6: View Profile button (Outlined)
              Padding(
                padding: EdgeInsets.only(top: verticalSpacing + 4),
                child: SizedBox(
                  width: double.infinity,
                  height: isSmallScreen ? 28 : 32,
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppColors.accent,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: Text(
                      isLocked ? 'Locked' : 'View Profile',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: buttonSize,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey : AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow([double? fontSize]) {
    final size = fontSize ?? 11.0;
    if (isOnline) {
      return Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Online now',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size,
              color: AppColors.success,
            ),
          ),
        ],
      );
    }
    if (lastSeen != null && lastSeen!.isNotEmpty) {
      return Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Last seen $lastSeen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}