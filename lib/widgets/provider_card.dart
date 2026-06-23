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
        child: isHorizontal ? _buildHorizontalCard() : _buildVerticalCard(),
      ),
    );
  }

  Widget _buildHorizontalCard() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64, height: 64,
              child: photoUrl != null
                  ? Image.network(photoUrl!, fit: BoxFit.cover)
                  : Container(color: AppColors.primary.withAlpha(26), child: Icon(Icons.person, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary))),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    SvgPicture.asset('assets/icons/verified.svg', width: 14, height: 14, colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn)),
                  ],
                ]),
                const SizedBox(height: 2),
                _buildStatusRow(),
                const SizedBox(height: 3),
                Text(services.take(2).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Row(children: [
                  SvgPicture.asset('assets/icons/star.svg', width: 12, height: 12, colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn)),
                  const SizedBox(width: 3),
                  Text('$rating ($reviewCount)', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  SvgPicture.asset('assets/icons/map_pin.svg', width: 12, height: 12, colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
                  const SizedBox(width: 3),
                  Flexible(child: Text('${distanceKm.toStringAsFixed(1)} km', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          child: SizedBox(
            height: 120, width: double.infinity,
            child: photoUrl != null
                ? Image.network(photoUrl!, fit: BoxFit.cover)
                : Container(color: AppColors.primary.withAlpha(26), child: Icon(Icons.person, color: AppColors.primary, size: 36)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary))),
                if (isVerified) ...[
                  const SizedBox(width: 3),
                  SvgPicture.asset('assets/icons/verified.svg', width: 14, height: 14, colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn)),
                ],
              ]),
              _buildStatusRow(),
              const SizedBox(height: 5),
              Text(services.take(2).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 5),
              Row(children: [
                SvgPicture.asset('assets/icons/star.svg', width: 12, height: 12, colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn)),
                const SizedBox(width: 3),
                Flexible(child: Text('$rating ($reviewCount)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                const Spacer(),
                SvgPicture.asset('assets/icons/map_pin.svg', width: 12, height: 12, colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn)),
                const SizedBox(width: 3),
                Flexible(child: Text('${distanceKm.toStringAsFixed(1)} km', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary))),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    if (isOnline) {
      return Row(
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          const Text('Online now', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.success)),
        ],
      );
    }
    if (lastSeen != null && lastSeen!.isNotEmpty) {
      return Row(
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Flexible(child: Text('Last seen $lastSeen', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary))),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}