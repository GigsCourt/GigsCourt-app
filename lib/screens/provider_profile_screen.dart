import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  final _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  bool _isEarlyAccess = false;
  bool _isSaved = false;

  // Address + Distance from Supabase
  String _providerAddress = '';
  double? _distanceKm;
  bool _isDistanceLoading = false;

  StreamSubscription? _userStream;

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

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = false;
    _loadProfile();
    _listenToRealTimeUpdates();
  }

  @override
  void dispose() {
    _userStream?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final userDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.providerId)
          .get();

      final savedFuture = _currentUser != null
          ? FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUser.uid)
              .get()
          : Future.value(null);

      final userDoc = await userDocFuture;
      final savedDoc = await savedFuture;

      if (!userDoc.exists) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final userData = userDoc.data()!;

      // Load services from Supabase
      List<Map<String, dynamic>> services = [];
      final serviceIds = List<int>.from(userData['services'] ?? []);
      if (serviceIds.isNotEmpty) {
        try {
          final namesData = await _supabase.rpc('get_service_names', params: {
            'service_ids': serviceIds,
          });
          services = List<Map<String, dynamic>>.from(namesData);
        } catch (_) {}
      }

      // Check if saved
      bool isSaved = false;
      if (savedDoc != null && savedDoc.exists) {
        final savedProviders = List<String>.from(savedDoc.data()?['savedProviders'] ?? []);
        isSaved = savedProviders.contains(widget.providerId);
      }

      if (mounted) {
        setState(() {
          _userData = userData;
          _services = services;
          _workPhotos = List<String>.from(userData['workPhotos'] ?? []);
          _isSaved = isSaved;
          _isLoading = false;
        });
      }

      _loadProviderLocation();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProviderLocation() async {
    if (mounted) {
      setState(() {
        _isDistanceLoading = true;
      });
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _fetchAddressFallback();
        if (mounted) {
          setState(() {
            _isDistanceLoading = false;
          });
        }
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
          ),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        await _fetchAddressFallback();
        if (mounted) {
          setState(() {
            _isDistanceLoading = false;
          });
        }
        return;
      }

      try {
        final result = await _supabase
            .rpc('find_all_providers', params: {
              'p_lat': position.latitude,
              'p_lng': position.longitude,
            })
            .timeout(const Duration(seconds: 5));

        final providers = List<Map<String, dynamic>>.from(result);

        final match = providers
            .where((p) => p['user_id'] == widget.providerId)
            .firstOrNull;

        if (match != null) {
          final distanceInMeters = (match['distance_meters'] as num?)?.toDouble() ?? 0;
          final address = match['address'] as String? ?? '';

          if (mounted) {
            setState(() {
              _distanceKm = distanceInMeters / 1000.0;
              _providerAddress = address;
              _isDistanceLoading = false;
            });
          }
        } else {
          await _fetchAddressFallback();
          if (mounted) {
            setState(() {
              _isDistanceLoading = false;
            });
          }
        }
      } catch (_) {
        await _fetchAddressFallback();
        if (mounted) {
          setState(() {
            _isDistanceLoading = false;
          });
        }
      }
    } catch (_) {
      await _fetchAddressFallback();
      if (mounted) {
        setState(() {
          _isDistanceLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAddressFallback() async {
    try {
      final result = await _supabase
          .from('provider_locations')
          .select('address')
          .eq('user_id', widget.providerId)
          .maybeSingle();

      if (result != null && result['address'] != null) {
        if (mounted) {
          setState(() {
            _providerAddress = result['address'] as String;
          });
        }
      }
    } catch (_) {}
  }

  void _listenToRealTimeUpdates() {
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.providerId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _userData = doc.data());
      }
    });
  }

  // ========== GETTERS ==========

  bool get _isSubscribed =>
      _userData?['subscriptionStatus'] == 'premium';

  bool get _canShowOnlineStatus =>
      _isEarlyAccess || _isSubscribed;

  bool get _canContact {
    if (_isEarlyAccess) return true;
    final status = _userData?['subscriptionStatus'] ?? 'free';
    return status == 'free' || status == 'premium';
  }

  // ========== SAVE / UNSAVE ==========

  Future<void> _toggleSave() async {
    if (_currentUser == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);

    setState(() {
      _isSaved = !_isSaved;
    });

    try {
      if (_isSaved) {
        await userRef.update({
          'savedProviders': FieldValue.arrayUnion([widget.providerId]),
        });
      } else {
        await userRef.update({
          'savedProviders': FieldValue.arrayRemove([widget.providerId]),
        });
      }
    } catch (e) {
      // Revert on failure
      setState(() {
        _isSaved = !_isSaved;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update saved providers.')),
        );
      }
    }
  }

  // ========== CHAT ==========

  Future<void> _startChat() async {
    if (_currentUser == null || !_canContact) {
      _showLockedToast();
      return;
    }

    final existingChat = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUser.uid)
        .get();

    String? existingChatId;
    for (final doc in existingChat.docs) {
      final participants = List<String>.from(doc.data()['participants'] ?? []);
      if (participants.contains(widget.providerId)) {
        existingChatId = doc.id;
        break;
      }
    }

    if (existingChatId != null) {
      if (mounted) {
        Navigator.of(context).pushNamed('/chat-conversation', arguments: {
          'chatId': existingChatId,
          'otherUserId': widget.providerId,
          'otherUserName': _userData?['displayName'] ?? 'Unknown',
        });
      }
      return;
    }

    final chatRef = await FirebaseFirestore.instance.collection('chats').add({
      'participants': [_currentUser.uid, widget.providerId],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    if (!_isEarlyAccess) {
      _trackEngagement('lead');
    }

    if (mounted) {
      Navigator.of(context).pushNamed('/chat-conversation', arguments: {
        'chatId': chatRef.id,
        'otherUserId': widget.providerId,
        'otherUserName': _userData?['displayName'] ?? 'Unknown',
      });
    }
  }

  Future<void> _trackEngagement(String type) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse('https://us-central1-gigs-court.cloudfunctions.net/trackEngagement'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'providerId': widget.providerId,
          'type': type,
        }),
      );
    } catch (_) {}
  }

  void _showLockedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This provider is not currently accepting new clients.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ========== REPORT ==========

  Future<void> _reportProvider() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Report Provider',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        content: const Text('Why are you reporting this provider?',
            style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'Inappropriate content'),
            child: const Text('Inappropriate', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'Fake profile'),
            child: const Text('Fake Profile', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'Other'),
            child: const Text('Other', style: TextStyle(fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (reason != null && _currentUser != null) {
      await FirebaseFirestore.instance.collection('tickets').add({
        'type': 'report',
        'submittedBy': _currentUser.uid,
        'targetUserId': widget.providerId,
        'subject': reason,
        'message': '',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    }
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(13.0);
    final photoColumns = _getPhotoGridColumns();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text('Profile',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.primary),
        body: const Center(
          child: Text(
            'Provider not found.',
            style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final name = _userData!['displayName'] ?? 'Unknown';
    final bio = _userData!['bio'] ?? '';
    final photoUrl = _userData!['photoUrl'];
    final rating = (_userData!['averageRating'] ?? 0.0).toDouble();
    final reviewCount = _userData!['reviewCount'] ?? 0;
    final isOnline = _userData?['isOnline'] ?? false;
    final lastSeen = _userData?['lastSeen'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          name,
          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report',
            onPressed: _reportProvider,
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
                  if (_isSubscribed) ...[
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
            if (_canShowOnlineStatus) ...[
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
            ],

            // ========== STATS ROW ==========
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStat(rating.toStringAsFixed(1), 'Rating'),
                _buildDivider(),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      '/reviews',
                      arguments: widget.providerId,
                    );
                  },
                  child: _buildStat('$reviewCount', 'Reviews'),
                ),
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

            // ========== ADDRESS ==========
            if (_providerAddress.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/map_pin.svg',
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _providerAddress,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize + 1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            // ========== DISTANCE ==========
            if (_distanceKm != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.straighten,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_distanceKm!.toStringAsFixed(1)} km away',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize + 1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else if (_isDistanceLoading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.straighten,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Calculating distance...',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else if (_providerAddress.isNotEmpty) ...[
              const SizedBox(height: 12),
            ],

            // ========== CHAT + SAVE BUTTONS ==========
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _canContact ? _startChat : _showLockedToast,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Chat',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _toggleSave,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _isSaved ? AppColors.primary : AppColors.primary.withAlpha(51),
                      ),
                      backgroundColor: _isSaved ? AppColors.primary.withAlpha(20) : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      _isSaved ? 'Saved' : 'Save',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _isSaved ? AppColors.primary : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ========== WORK PHOTOS ==========
            if (_workPhotos.isNotEmpty) ...[
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
                  return ClipRRect(
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
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ========== WIDGET HELPERS ==========

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