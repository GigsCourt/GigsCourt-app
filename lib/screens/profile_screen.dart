import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';
import '../widgets/skeleton_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _providerData;
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final providerDoc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();

      final serviceIds = List<int>.from(providerDoc.data()?['services'] ?? []);
      List<Map<String, dynamic>> services = [];
      if (serviceIds.isNotEmpty) {
        final namesData = await _supabase.rpc('get_service_names', params: {'service_ids': serviceIds});
        services = List<Map<String, dynamic>>.from(namesData);
      }

      setState(() {
        _userData = userDoc.data();
        _providerData = providerDoc.data();
        _services = services;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _userData == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.primary, title: const Text('Profile', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600))),
        body: _buildSkeleton(),
      );
    }

    final name = _userData?['displayName'] ?? 'Unknown';
    final photoUrl = _userData?['photoUrl'];
    final isVerified = _providerData?['subscriptionStatus'] == 'premium';
    final rating = (_providerData?['averageRating'] ?? 0.0).toDouble();
    final followerCount = _userData?['followerCount'] ?? 0;
    final followingCount = _userData?['followingCount'] ?? 0;
    final subscriptionStatus = _providerData?['subscriptionStatus'] ?? 'free';
    final workPhotos = List<String>.from(_providerData?['workPhotos'] ?? []);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Profile', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.menu), onPressed: () => Navigator.of(context).pushNamed('/settings')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(80),
                child: SizedBox(
                  width: 140, height: 140,
                  child: photoUrl != null
                      ? Image.network(ImageOptimizer.medium(photoUrl, width: 280, height: 280), fit: BoxFit.cover)
                      : Container(color: AppColors.primary.withAlpha(26), child: Icon(Icons.person, size: 60, color: AppColors.primary)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.textPrimary))),
                if (isVerified) ...[
                  const SizedBox(width: 6),
                  SvgPicture.asset('assets/icons/verified.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(onTap: () => Navigator.of(context).pushNamed('/provider-profile', arguments: FirebaseAuth.instance.currentUser?.uid), child: _buildStat('$rating', 'Reviews')),
                _buildDivider(),
                _buildStat('$followerCount', 'Followers'),
                _buildDivider(),
                _buildStat('$followingCount', 'Following'),
              ],
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/subscription'),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withAlpha(26))),
                child: Row(
                  children: [
                    Icon(subscriptionStatus == 'premium' ? Icons.verified : Icons.workspace_premium_outlined, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(subscriptionStatus == 'premium' ? 'Premium' : 'Free', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_services.isNotEmpty) ...[
              _buildSectionTile('My Services', '${_services.length} services', () => Navigator.of(context).pushNamed('/edit-profile')),
              const SizedBox(height: 8),
            ],
            _buildSectionTile('Work Photos', '${workPhotos.length}/15 photos', () => Navigator.of(context).pushNamed('/edit-profile')),
            const SizedBox(height: 8),
            _buildSectionTile('Following', '$followingCount', () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Center(child: SkeletonLoader(width: 140, height: 140, borderRadius: 70)),
          const SizedBox(height: 16),
          const Center(child: SkeletonLoader(width: 150, height: 22)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SkeletonLoader(width: 50, height: 30),
            const SizedBox(width: 20),
            const SkeletonLoader(width: 50, height: 30),
            const SizedBox(width: 20),
            const SkeletonLoader(width: 50, height: 30),
          ]),
          const SizedBox(height: 24),
          const SkeletonLoader(height: 60),
          const SizedBox(height: 16),
          const SkeletonLoader(height: 60),
          const SizedBox(height: 8),
          const SkeletonLoader(height: 60),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary)),
      Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
    ]);
  }

  Widget _buildDivider() {
    return Container(height: 24, width: 1, color: AppColors.primary.withAlpha(26), margin: const EdgeInsets.symmetric(horizontal: 16));
  }

  Widget _buildSectionTile(String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withAlpha(26))),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
          ]),
          const Spacer(),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}