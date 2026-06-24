import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';
import '../services/imagekit_service.dart';
import '../widgets/skeleton_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _remoteConfig = FirebaseRemoteConfig.instance;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  bool _isEarlyAccess = false;
  bool _isUploading = false;
  StreamSubscription? _userStream;
  
  // Follower/Following counts from sub-collections
  int _followerCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !_remoteConfig.getBool('subscriptions_enforced');
    _loadProfile();
  }

  @override
  void dispose() {
    _userStream?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data()!;
      final serviceIds = List<int>.from(userData['services'] ?? []);
      List<Map<String, dynamic>> services = [];
      if (serviceIds.isNotEmpty) {
        final namesData = await _supabase.rpc('get_service_names', params: {'service_ids': serviceIds});
        services = List<Map<String, dynamic>>.from(namesData);
      }

      setState(() {
        _userData = userData;
        _services = services;
        _workPhotos = List<String>.from(userData['workPhotos'] ?? []);
        _isLoading = false;
      });

      // Listen for real-time updates
      _userStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((doc) {
        if (doc.exists && mounted) {
          setState(() {
            _userData = doc.data();
            _services = services;
            _workPhotos = List<String>.from(doc.data()?['workPhotos'] ?? []);
          });
        }
      });

      // Load follower and following counts from sub-collections
      _loadFollowerAndFollowingCounts(user.uid);

    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFollowerAndFollowingCounts(String userId) async {
    try {
      // Listen to followers count
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('followers')
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _followerCount = snapshot.docs.length;
          });
        }
      });

      // Listen to following count
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('following')
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _followingCount = snapshot.docs.length;
          });
        }
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _addWorkPhoto() async {
    if (_workPhotos.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 15 photos. Delete some to add more.')),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _isUploading = true);

    final result = await ImageKitService.uploadImage(
      File(picked.path),
      'work_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (mounted && result['success'] == true) {
      final newPhotos = [..._workPhotos, result['url'] as String];
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'workPhotos': newPhotos,
      });
      setState(() {
        _workPhotos = newPhotos;
        _isUploading = false;
      });
    } else {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _deleteWorkPhoto(int index) async {
    final newPhotos = List<String>.from(_workPhotos);
    newPhotos.removeAt(index);
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
      'workPhotos': newPhotos,
    });
    setState(() => _workPhotos = newPhotos);
  }

  void _viewPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(
          photos: _workPhotos,
          initialIndex: index,
          onDelete: (idx) {
            _deleteWorkPhoto(idx);
            if (_workPhotos.length <= 1) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _showPhotoOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('View Full Screen', style: TextStyle(fontFamily: 'Inter')),
              onTap: () {
                Navigator.pop(ctx);
                _viewPhoto(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete Photo', style: TextStyle(fontFamily: 'Inter', color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteWorkPhoto(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ========== RESPONSIVE HELPERS ==========

  double _getFontSize(double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) {
      return baseSize * 0.9;
    } else if (screenWidth > 600) {
      return baseSize * 1.1;
    }
    return baseSize;
  }

  int _getPhotoGridColumns() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return 3;
    if (screenWidth < 600) return 3;
    if (screenWidth < 900) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(16.0);
    final photoColumns = _getPhotoGridColumns();

    if (_isLoading && _userData == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text(
            'Profile',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
          ),
        ),
        body: _buildSkeleton(),
      );
    }

    final name = _userData?['displayName'] ?? 'Unknown';
    final photoUrl = _userData?['photoUrl'];
    final isVerified = _userData?['subscriptionStatus'] == 'premium';
    final rating = (_userData?['averageRating'] ?? 0.0).toDouble();
    final reviewCount = _userData?['reviewCount'] ?? 0;
    final subscriptionStatus = _userData?['subscriptionStatus'] ?? 'free';
    final leadCount = _userData?['leadCount'] ?? 0;
    final maxLeads = 10;
    final maxReviews = 5;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'Profile',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Photo
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(80),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: photoUrl != null
                      ? Image.network(
                          ImageOptimizer.medium(photoUrl, width: 280, height: 280),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.primary.withAlpha(26),
                              child: Icon(Icons.person, size: 60, color: AppColors.primary),
                            );
                          },
                        )
                      : Container(
                          color: AppColors.primary.withAlpha(26),
                          child: Icon(Icons.person, size: 60, color: AppColors.primary),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Name + Verified Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize + 6,
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
                    colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Stats (Reviews, Followers, Following)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed(
                    '/provider-profile',
                    arguments: FirebaseAuth.instance.currentUser?.uid,
                  ),
                  child: _buildStat(rating.toStringAsFixed(1), 'Reviews'),
                ),
                _buildDivider(),
                _buildStat('$_followerCount', 'Followers'),
                _buildDivider(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/following'),
                  child: _buildStat('$_followingCount', 'Following'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Threshold progress (only post-EA, only for free users)
            if (!_isEarlyAccess && subscriptionStatus == 'free') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withAlpha(26)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Progress',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$leadCount / $maxLeads leads',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: leadCount / maxLeads,
                                  backgroundColor: AppColors.primary.withAlpha(26),
                                  color: AppColors.primary,
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$reviewCount / $maxReviews reviews',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: reviewCount / maxReviews,
                                  backgroundColor: AppColors.accent.withAlpha(26),
                                  color: AppColors.accent,
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (leadCount >= maxLeads || reviewCount >= maxReviews) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pushNamed('/subscription'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Subscribe Now',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Subscription card
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/subscription'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withAlpha(26)),
                ),
                child: Row(
                  children: [
                    Icon(
                      subscriptionStatus == 'premium'
                          ? Icons.verified
                          : Icons.workspace_premium_outlined,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      subscriptionStatus == 'premium' ? 'Premium' : 'Free',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ========== SERVICES ==========
            if (_services.isNotEmpty) ...[
              const Text(
                'My Services',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.textPrimary,
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
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                      ),
                    ),
                    backgroundColor: AppColors.primary.withAlpha(20),
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Work Photos
            const Text(
              'Work Photos',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            if (_workPhotos.length < 15)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _addWorkPhoto,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: Text(
                      _isUploading ? 'Uploading...' : 'Add Photo',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withAlpha(51)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '15/15 — Max reached',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary),
                ),
              ),

            if (_workPhotos.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: photoColumns,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _workPhotos.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _viewPhoto(index),
                    onLongPress: () => _showPhotoOptions(index),
                    child: ClipRRect(
                      borderRadius: _getPhotoBorderRadius(index, _workPhotos.length),
                      child: Image.network(
                        ImageOptimizer.thumbnail(_workPhotos[index]),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.primary.withAlpha(26),
                            child: const Icon(Icons.broken_image, color: AppColors.textSecondary),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SkeletonLoader(width: 50, height: 30),
              const SizedBox(width: 20),
              const SkeletonLoader(width: 50, height: 30),
              const SizedBox(width: 20),
              const SkeletonLoader(width: 50, height: 30),
            ],
          ),
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
    return Column(
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

class _PhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  final Function(int) onDelete;

  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '${_currentIndex + 1} of ${widget.photos.length}',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              widget.onDelete(_currentIndex);
              if (widget.photos.length <= 1) {
                Navigator.of(context).pop();
              } else {
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                ImageOptimizer.original(widget.photos[index]),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 48,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}