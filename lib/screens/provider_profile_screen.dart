import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String providerId;

  const ProviderProfileScreen({super.key, required this.providerId});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _providerData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  double? _distanceKm;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.providerId)
          .get();

      final providerDoc = await FirebaseFirestore.instance
          .collection('providers')
          .doc(widget.providerId)
          .get();

      if (!userDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _userData = userDoc.data();
        _providerData = providerDoc.data();
        _workPhotos = List<String>.from(_providerData?['workPhotos'] ?? []);
      });

      final serviceIds = List<int>.from(_providerData?['services'] ?? []);
      if (serviceIds.isNotEmpty) {
        final namesData = await _supabase.rpc('get_service_names', params: {
          'service_ids': serviceIds,
        });
        _services = List<Map<String, dynamic>>.from(namesData);
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
          ),
        );

        final nearbyData = await _supabase.rpc('find_nearby_providers', params: {
          'p_lat': position.latitude,
          'p_lng': position.longitude,
          'p_radius_meters': 50000,
        });

        final nearbyList = List<Map<String, dynamic>>.from(nearbyData);
        final match = nearbyList
            .where((p) => p['user_id'] == widget.providerId)
            .firstOrNull;
        if (match != null) {
          _distanceKm = (match['distance_meters'] as num) / 1000.0;
        }
      } catch (_) {}

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.primary),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.primary),
        body: const Center(
          child: Text('Provider not found.',
              style:
                  TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
        ),
      );
    }

    final name = _userData!['displayName'] ?? 'Unknown';
    final bio = _userData!['bio'] ?? '';
    final photoUrl = _userData!['photoUrl'];
    final isVerified = _providerData?['subscriptionStatus'] == 'premium';
    final isOnline = _providerData?['isOnline'] ?? false;
    final rating = (_providerData?['averageRating'] ?? 0.0).toDouble();
    final followerCount = _userData!['followerCount'] ?? 0;
    final followingCount = _userData!['followingCount'] ?? 0;
    final address = _providerData?['address'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(name,
            style: const TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(80),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: photoUrl != null
                      ? Image.network(
                          ImageOptimizer.medium(photoUrl,
                              width: 280, height: 280),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: AppColors.primary.withAlpha(26),
                          child: Icon(Icons.person,
                              size: 60, color: AppColors.primary),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 6),
                  SvgPicture.asset(
                    'assets/icons/verified.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      AppColors.accent,
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ],
            ),
            if (isOnline) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Online now',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStat('$rating', 'Reviews', () {}),
                _buildDivider(),
                _buildStat('$followerCount', 'Followers', () {}),
                _buildDivider(),
                _buildStat('$followingCount', 'Following', () {}),
              ],
            ),
            const SizedBox(height: 12),
            if (address.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/map_pin.svg',
                    width: 14,
                    height: 14,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _distanceKm != null
                        ? '${_distanceKm!.toStringAsFixed(1)} km away'
                        : address,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (bio.isNotEmpty) ...[
              Text(
                bio,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_services.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Services',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _services.map((service) {
                  return Chip(
                    label: Text(
                      service['name'],
                      style:
                          const TextStyle(fontFamily: 'Inter', fontSize: 13),
                    ),
                    backgroundColor: AppColors.primary.withAlpha(20),
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child:
                      _buildButton('Follow', Icons.person_add_outlined, () {}),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      _buildButton('Chat', Icons.chat_bubble_outline, () {}),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton('Call', Icons.call_outlined, () {}),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_workPhotos.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Work Photos',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _workPhotos.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius:
                        _getPhotoBorderRadius(index, _workPhotos.length),
                    child: Image.network(
                      ImageOptimizer.thumbnail(_workPhotos[index]),
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'Report Provider',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 24,
      width: 1,
      color: AppColors.primary.withAlpha(26),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  BorderRadius _getPhotoBorderRadius(int index, int total) {
    final row = index ~/ 3;
    final col = index % 3;
    final totalRows = (total / 3).ceil();
    final isLastRow = row == totalRows - 1;
    final itemsInLastRow = total % 3 == 0 ? 3 : total % 3;
    final isLastInRow = isLastRow && col == itemsInLastRow - 1;

    return BorderRadius.only(
      topLeft: Radius.circular(row == 0 && col == 0 ? 12 : 0),
      topRight: Radius.circular(row == 0 && col == 2 ? 12 : 0),
      bottomLeft: Radius.circular(isLastRow && col == 0 ? 12 : 0),
      bottomRight: Radius.circular(isLastInRow ? 12 : 0),
    );
  }
}