import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/cache_service.dart';
import '../widgets/provider_card.dart';
import '../widgets/skeleton_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final _remoteConfig = FirebaseRemoteConfig.instance;
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _featuredProviders = [];
  List<Map<String, dynamic>> _allProviders = [];
  bool _isLoading = true;
  bool _isEarlyAccess = false;
  bool _showScrollToTop = false;
  double? _userLat;
  double? _userLng;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !_remoteConfig.getBool('subscriptions_enforced');
    _scrollController.addListener(_onScroll);
    _getLocationAndLoadProviders();
    // Fallback: if loading takes more than 10 seconds, show empty state
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      setState(() {
        _showScrollToTop = _scrollController.offset > 400;
      });
    }
  }

  Future<void> _getLocationAndLoadProviders() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _isLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      _userLat = position.latitude;
      _userLng = position.longitude;

      await _loadProviders();

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      ).listen((position) {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _loadProviders();
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProviders() async {
    if (_userLat == null || _userLng == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final nearbyData = await _supabase.rpc('find_all_providers', params: {
        'p_lat': _userLat,
        'p_lng': _userLng,
      });

      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);

      if (nearbyUsers.isEmpty) {
        setState(() {
          _featuredProviders = [];
          _allProviders = [];
          _isLoading = false;
        });
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final filteredUsers = nearbyUsers
          .where((p) => p['user_id'] != currentUserId)
          .toList();

      if (filteredUsers.isEmpty) {
        setState(() {
          _featuredProviders = [];
          _allProviders = [];
          _isLoading = false;
        });
        return;
      }

      final userFutures = filteredUsers.map((supa) {
        final id = supa['user_id'] as String;
        return FirebaseFirestore.instance.collection('users').doc(id).get();
      }).toList();

      final userDocs = await Future.wait(userFutures);

      final allServiceIds = <int>{};
      final providersRaw = <Map<String, dynamic>>[];

      for (int i = 0; i < filteredUsers.length; i++) {
        final supa = filteredUsers[i];
        final userDoc = userDocs[i];
        if (!userDoc.exists) continue;

        final id = supa['user_id'] as String;
        final userData = userDoc.data()!;
        final serviceIds = List<int>.from(userData['services'] ?? []);
        allServiceIds.addAll(serviceIds);

        providersRaw.add({
          'userId': id,
          'name': userData['displayName'] ?? 'Unknown',
          'photoUrl': userData['photoUrl'],
          'isVerified': userData['subscriptionStatus'] == 'premium',
          'subscriptionStatus': userData['subscriptionStatus'] ?? 'free',
          'isOnline': _isEarlyAccess
              ? (userData['isOnline'] ?? false)
              : (userData['subscriptionStatus'] == 'premium' && (userData['isOnline'] ?? false)),
          'serviceIds': serviceIds,
          'rating': (userData['averageRating'] ?? 0.0).toDouble(),
          'reviewCount': userData['reviewCount'] ?? 0,
          'distanceKm': (supa['distance_meters'] as num) / 1000.0,
          'lastReviewedAt': userData['lastReviewedAt'],
        });
      }

      if (providersRaw.isEmpty) {
        setState(() {
          _featuredProviders = [];
          _allProviders = [];
          _isLoading = false;
        });
        return;
      }

      Map<int, String> serviceNames = CacheService.get<Map<int, String>>('service_names') ?? {};
      final uncachedIds = allServiceIds.where((id) => !serviceNames.containsKey(id)).toList();

      if (uncachedIds.isNotEmpty) {
        final namesData = await _supabase.rpc('get_service_names', params: {
          'service_ids': uncachedIds,
        });
        for (final row in List<Map<String, dynamic>>.from(namesData)) {
          serviceNames[row['id'] as int] = row['name'] as String;
        }
        CacheService.set('service_names', serviceNames, ttl: const Duration(hours: 24));
      }

      final providers = providersRaw.map((p) {
        final names = (p['serviceIds'] as List<int>)
            .map((id) => serviceNames[id] ?? id.toString())
            .toList();
        return {...p, 'services': names};
      }).toList();

      providers.sort((a, b) {
        final distCompare = (a['distanceKm'] as double).compareTo(b['distanceKm'] as double);
        if (distCompare != 0) return distCompare;
        final aLast = a['lastReviewedAt'];
        final bLast = b['lastReviewedAt'];
        if (aLast != null && bLast != null) {
          final dateCompare = (bLast as dynamic).compareTo(aLast as dynamic);
          if (dateCompare != 0) return dateCompare;
        }
        final reviewCompare = (b['reviewCount'] as int).compareTo(a['reviewCount'] as int);
        if (reviewCompare != 0) return reviewCompare;
        if ((a['rating'] as double) < 3.0) return 1;
        if ((b['rating'] as double) < 3.0) return -1;
        return (b['rating'] as double).compareTo(a['rating'] as double);
      });

      setState(() {
        _featuredProviders = providers.where((p) => p['isVerified'] == true).toList();
        _allProviders = providers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _handleProviderTap(Map<String, dynamic> provider) {
    if (!_isEarlyAccess && provider['subscriptionStatus'] == 'locked') {
      _sendBlockedNotification(provider['userId']);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This provider is not currently accepting new clients.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      Navigator.of(context).pushNamed('/provider-profile', arguments: provider['userId']);
    }
  }

  Future<void> _sendBlockedNotification(String providerId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse('https://us-central1-gigs-court.cloudfunctions.net/createNotification'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'userId': providerId,
          'title': 'Someone tried to view your profile',
          'body': 'A potential client tried to contact you. Subscribe to accept new clients.',
          'type': 'locked',
        }),
      );
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _loadProviders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GigsCourt',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20)),
            if (_isEarlyAccess) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Early Access',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Colors.white)),
              ),
            ],
          ],
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.of(context).pushNamed('/notifications'),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading && _allProviders.isEmpty
              ? _buildSkeletonGrid()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_featuredProviders.isNotEmpty) ...[
                        _buildSectionHeader('Featured'),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _featuredProviders.length,
                            itemBuilder: (context, index) {
                              final p = _featuredProviders[index];
                              return ProviderCard(
                                name: p['name'], photoUrl: p['photoUrl'],
                                isVerified: p['isVerified'], isOnline: p['isOnline'],
                                services: List<String>.from(p['services']),
                                rating: p['rating'], reviewCount: p['reviewCount'],
                                distanceKm: p['distanceKm'], isHorizontal: true,
                                onTap: () => _handleProviderTap(p),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildSectionHeader('All Providers'),
                      const SizedBox(height: 12),
                      if (_allProviders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No providers found nearby.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
                          itemCount: _allProviders.length,
                          itemBuilder: (context, index) {
                            final p = _allProviders[index];
                            return ProviderCard(
                              name: p['name'], photoUrl: p['photoUrl'],
                              isVerified: p['isVerified'], isOnline: p['isOnline'],
                              services: List<String>.from(p['services']),
                              rating: p['rating'], reviewCount: p['reviewCount'],
                              distanceKm: p['distanceKm'],
                              onTap: () => _handleProviderTap(p),
                            );
                          },
                        ),
                    ],
                  ),
                ),
          if (_showScrollToTop)
            Positioned(
              bottom: 20, right: 20,
              child: FloatingActionButton.small(
                onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonLoader(width: 100, height: 18),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, itemCount: 3,
            itemBuilder: (_, _) => const ProviderCardSkeleton(isHorizontal: true),
          ),
        ),
        const SizedBox(height: 24),
        const SkeletonLoader(width: 120, height: 18),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: 6,
          itemBuilder: (_, _) => const ProviderCardSkeleton(),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title,
        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary));
  }
}