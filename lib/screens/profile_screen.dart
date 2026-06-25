import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String _uploadStatus = '';
  StreamSubscription? _userStream;

  // Saved providers
  List<String> _savedProviders = [];

  @override
  void initState() {
    super.initState();
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

      _savedProviders = List<String>.from(userData['savedProviders'] ?? []);

      setState(() {
        _userData = userData;
        _services = services;
        _workPhotos = List<String>.from(userData['workPhotos'] ?? []);
        _isLoading = false;
      });

      _userStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((doc) {
        if (doc.exists && mounted) {
          final data = doc.data()!;
          final newSaved = List<String>.from(data['savedProviders'] ?? []);
          setState(() {
            _userData = data;
            _savedProviders = newSaved;
            _workPhotos = List<String>.from(data['workPhotos'] ?? []);
          });
        }
      });

    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ========== MULTIPLE PHOTO UPLOAD ==========

  Future<void> _addWorkPhotos() async {
    final remaining = 15 - _workPhotos.length;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 15 photos reached.')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);

    if (picked.isEmpty) return;

    final selected = picked.take(remaining).toList();

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading 0/${selected.length} photos...';
    });

    final newPhotos = List<String>.from(_workPhotos);
    int successCount = 0;

    for (int i = 0; i < selected.length; i++) {
      final image = selected[i];

      if (mounted) {
        setState(() {
          _uploadStatus = 'Uploading ${i + 1}/${selected.length} photos...';
        });
      }

      final result = await ImageKitService.uploadImage(
        File(image.path),
        'work_${DateTime.now().millisecondsSinceEpoch}_$i',
      );

      if (result['success'] == true) {
        newPhotos.add(result['url'] as String);
        successCount++;
      }
    }

    if (successCount > 0) {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'workPhotos': newPhotos,
      });
      if (mounted) {
        setState(() {
          _workPhotos = newPhotos;
          _isUploading = false;
          _uploadStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount photo${successCount > 1 ? 's' : ''} uploaded successfully.')),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
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
    if (screenWidth < 380) return baseSize * 0.9;
    if (screenWidth > 600) return baseSize * 1.1;
    return baseSize;
  }

  int _getPhotoGridColumns() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return 3;
    if (screenWidth < 600) return 3;
    if (screenWidth < 900) return 4;
    return 5;
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(13.0);
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
    final savedCount = _savedProviders.length;
    final subscriptionStatus = _userData?['subscriptionStatus'] ?? 'free';
    final leadCount = _userData?['leadCount'] ?? 0;
    final bio = _userData?['bio'] ?? '';
    final maxLeads = 10;
    final maxReviews = 5;
    final isOnline = _userData?['isOnline'] ?? false;
    final lastSeen = _userData?['lastSeen'];

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ========== PROFILE PHOTO ==========
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

            // ========== NAME + VERIFIED BADGE ==========
            Center(
              child: Row(
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
                        fontSize: fontSize + 9,
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
            ),
            const SizedBox(height: 4),

            // ========== ONLINE / LAST SEEN ==========
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.success : AppColors.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOnline
                        ? 'Online now'
                        : _formatLastSeen(lastSeen),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize,
                      color: isOnline ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ========== STATS ROW ==========
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStat(rating.toStringAsFixed(1), 'Rating'),
                _buildDivider(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed(
                    '/provider-profile',
                    arguments: FirebaseAuth.instance.currentUser?.uid,
                  ),
                  child: _buildStat('$reviewCount', 'Reviews'),
                ),
                _buildDivider(),
                _buildStat('$savedCount', 'Saved'),
              ],
            ),
            const SizedBox(height: 16),

            // ========== BIO (CENTERED) ==========
            if (bio.isNotEmpty) ...[
              Center(
                child: Text(
                  bio,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: fontSize + 2,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ========== SERVICES (CENTERED) ==========
            if (_services.isNotEmpty) ...[
              Center(
                child: const Text(
                  'Services',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: _services.map((service) {
                    return Chip(
                      label: Text(
                        service['name'],
                        style: TextStyle(fontFamily: 'Inter', fontSize: fontSize),
                      ),
                      backgroundColor: AppColors.primary.withAlpha(20),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ========== STATUS BAR ==========
            _buildStatusBar(
              subscriptionStatus: subscriptionStatus,
              leadCount: leadCount,
              reviewCount: reviewCount,
              maxLeads: maxLeads,
              maxReviews: maxReviews,
              fontSize: fontSize,
            ),
            const SizedBox(height: 16),

            // ========== WORK PHOTOS ==========
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Work Photos',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_workPhotos.length < 15)
                  TextButton(
                    onPressed: _isUploading ? null : _addWorkPhotos,
                    child: Text(
                      _isUploading ? _uploadStatus : 'Add Photos',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: fontSize,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  Text(
                    '15/15 Max',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

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

  Widget _buildStatusBar({
    required String subscriptionStatus,
    required int leadCount,
    required int reviewCount,
    required int maxLeads,
    required int maxReviews,
    required double fontSize,
  }) {
    if (subscriptionStatus == 'premium') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withAlpha(40)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: AppColors.success, size: 20),
            const SizedBox(width: 8),
            Text(
              'Premium ✅ Active',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: fontSize + 2,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }

    if (subscriptionStatus == 'locked') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withAlpha(40)),
        ),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pushNamed('/subscription'),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Subscribe to continue receiving clients',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                    color: AppColors.error,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppColors.error, size: 16),
            ],
          ),
        ),
      );
    }

    // Free status
    final leadsUsed = leadCount;
    final reviewsUsed = reviewCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free — $leadsUsed/$maxLeads leads used | $reviewsUsed/$maxReviews reviews used',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: leadCount / maxLeads,
                    backgroundColor: AppColors.primary.withAlpha(26),
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: reviewCount / maxReviews,
                    backgroundColor: AppColors.accent.withAlpha(26),
                    color: AppColors.accent,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),
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

  String _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Offline';
    final date = (lastSeen as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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

// ========== PHOTO VIEWER ==========

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
              if (widget.photos.length <= 1) Navigator.of(context).pop();
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