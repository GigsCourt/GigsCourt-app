import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../theme/app_theme.dart';
import '../services/cache_service.dart';
import '../widgets/provider_card.dart';
import '../widgets/skeleton_loader.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _remoteConfig = FirebaseRemoteConfig.instance;

  bool _isLoading = false;
  bool _isEarlyAccess = false;
  double _radiusKm = 10;
  double? _userLat;
  double? _userLng;
  String? _selectedService;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _providers = [];
  
  // Popular services chips
  List<Map<String, dynamic>> _popularServices = [];
  bool _isLoadingChips = false;

  // Filters
  bool _showOnlineOnly = false;
  bool _showPremiumOnly = false;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !_remoteConfig.getBool('subscriptions_enforced');
    _getLocationAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getLocationAndLoad() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
      
      await Future.wait([
        _loadAllServices(),
        _loadPopularServices(),
      ]);
    } catch (_) {}
  }

  Future<void> _loadAllServices() async {
    try {
      final data = await _supabase.rpc('get_all_services');
      setState(() {
        _services = List<Map<String, dynamic>>.from(data);
      });
    } catch (_) {}
  }

  Future<void> _loadPopularServices() async {
    if (_userLat == null || _userLng == null) return;
    
    setState(() => _isLoadingChips = true);
    
    try {
      final nearbyData = await _supabase.rpc('find_nearby_providers', params: {
        'p_lat': _userLat,
        'p_lng': _userLng,
        'p_radius_meters': (_radiusKm * 1000).toInt(),
      });
      
      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);
      
      if (nearbyUsers.isEmpty) {
        setState(() {
          _popularServices = [];
          _isLoadingChips = false;
        });
        return;
      }
      
      final userFutures = nearbyUsers.map((supa) {
        final id = supa['user_id'] as String;
        return FirebaseFirestore.instance.collection('users').doc(id).get();
      }).toList();
      
      final userDocs = await Future.wait(userFutures);
      
      final serviceCount = <int, int>{};
      for (final doc in userDocs) {
        if (!doc.exists) continue;
        final userData = doc.data()!;
        final serviceIds = List<int>.from(userData['services'] ?? []);
        for (final id in serviceIds) {
          serviceCount[id] = (serviceCount[id] ?? 0) + 1;
        }
      }
      
      final sortedIds = serviceCount.keys.toList()
        ..sort((a, b) => (serviceCount[b] ?? 0).compareTo(serviceCount[a] ?? 0));
      
      final topIds = sortedIds.take(15).toList();
      
      if (topIds.isEmpty) {
        setState(() {
          _popularServices = [];
          _isLoadingChips = false;
        });
        return;
      }
      
      final namesData = await _supabase.rpc('get_service_names', params: {
        'service_ids': topIds,
      });
      
      final nameMap = <int, String>{};
      for (final row in List<Map<String, dynamic>>.from(namesData)) {
        nameMap[row['id'] as int] = row['name'] as String;
      }
      
      final popular = topIds.map((id) {
        return {
          'id': id,
          'name': nameMap[id] ?? 'Unknown',
          'count': serviceCount[id] ?? 0,
        };
      }).toList();
      
      setState(() {
        _popularServices = popular;
        _isLoadingChips = false;
      });
    } catch (_) {
      setState(() => _isLoadingChips = false);
    }
  }

  Future<void> _searchServices(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final data = await _supabase.rpc('search_services', params: {
        'search_term': query,
      });
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(data).take(10).toList();
      });
    } catch (_) {}
  }

  void _selectService(Map<String, dynamic> service) {
    setState(() {
      _selectedService = service['name'];
      _searchController.text = service['name'];
      _searchResults = [];
    });
    _findProviders();
  }

  void _selectPopularService(Map<String, dynamic> service) {
    setState(() {
      _selectedService = service['name'];
      _searchController.text = service['name'];
      _searchResults = [];
    });
    _findProviders();
  }

  void _clearSelectedService() {
    setState(() {
      _selectedService = null;
      _searchController.clear();
      _providers = [];
    });
  }

  Future<void> _findProviders() async {
    if (_userLat == null || _userLng == null || _selectedService == null) return;
    setState(() => _isLoading = true);

    try {
      final nearbyData = await _supabase.rpc('find_nearby_providers', params: {
        'p_lat': _userLat,
        'p_lng': _userLng,
        'p_radius_meters': (_radiusKm * 1000).toInt(),
      });

      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);
      if (nearbyUsers.isEmpty) {
        setState(() {
          _providers = [];
          _isLoading = false;
        });
        return;
      }

      final userFutures = nearbyUsers.map((supa) {
        final id = supa['user_id'] as String;
        return FirebaseFirestore.instance.collection('users').doc(id).get();
      }).toList();

      final userDocs = await Future.wait(userFutures);

      final allServiceIds = <int>{};
      final providersRaw = <Map<String, dynamic>>[];

      for (int i = 0; i < nearbyUsers.length; i++) {
        final supa = nearbyUsers[i];
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
          'latitude': supa['latitude'],
          'longitude': supa['longitude'],
          'lastReviewedAt': userData['lastReviewedAt'],
          'lastSeen': _formatLastSeen(userData['lastSeen']),
        });
      }

      final serviceId = _services.firstWhere(
        (s) => s['name'] == _selectedService,
        orElse: () => {'id': -1},
      )['id'] as int;

      var filtered = providersRaw
          .where((p) => (p['serviceIds'] as List<int>).contains(serviceId))
          .toList();

      if (_showOnlineOnly) {
        filtered = filtered.where((p) => p['isOnline'] == true).toList();
      }
      if (_showPremiumOnly) {
        filtered = filtered.where((p) => p['isVerified'] == true).toList();
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

      final providers = filtered.map((p) {
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
        _providers = providers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String? _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return null;
    final date = (lastSeen as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  void _handleProviderTap(Map<String, dynamic> provider) {
  // ✅ FIX: Allow the provider to view their own profile
  final currentUser = FirebaseAuth.instance.currentUser;
  final isOwnProfile = currentUser?.uid == provider['userId'];

  if (!_isEarlyAccess && provider['subscriptionStatus'] == 'locked' && !isOwnProfile) {
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

  void _clearAllFilters() {
    setState(() {
      _radiusKm = 10;
      _showOnlineOnly = false;
      _showPremiumOnly = false;
      _selectedService = null;
      _searchController.clear();
      _providers = [];
      _searchResults = [];
    });
    _loadPopularServices();
  }

  // ========== RESPONSIVE HELPERS ==========

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth < 600) {
      return 2; // Phones
    } else if (screenWidth < 900) {
      return 3; // Small tablets
    } else {
      return 4; // Large tablets
    }
  }

  double _getAspectRatio(double screenWidth) {
    if (screenWidth < 600) {
      return 0.72; // Phones
    } else if (screenWidth < 900) {
      return 0.70; // Small tablets
    } else {
      return 0.68; // Large tablets
    }
  }

  double _getCardSpacing(double screenWidth) {
    if (screenWidth < 600) {
      return 12.0; // Phones
    } else {
      return 16.0; // Tablets
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(screenWidth);
    final aspectRatio = _getAspectRatio(screenWidth);
    final spacing = _getCardSpacing(screenWidth);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar (no app bar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _searchServices,
                    decoration: InputDecoration(
                      hintText: 'Search services...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(13),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final service = _searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              service['name'],
                              style: const TextStyle(fontFamily: 'Inter'),
                            ),
                            subtitle: Text(
                              service['category'],
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12),
                            ),
                            onTap: () => _selectService(service),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            
            // Popular Services Chips
            if (_popularServices.isNotEmpty || _isLoadingChips)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: _isLoadingChips
                    ? const SizedBox(
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _popularServices.length,
                          itemBuilder: (context, index) {
                            final service = _popularServices[index];
                            final isSelected = _selectedService == service['name'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  if (isSelected) {
                                    _clearSelectedService();
                                  } else {
                                    _selectPopularService(service);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.primary.withAlpha(20),
                                    borderRadius: BorderRadius.circular(20),
                                    border: isSelected
                                        ? null
                                        : Border.all(
                                            color: AppColors.primary.withAlpha(40),
                                          ),
                                  ),
                                  child: Text(
                                    service['name'],
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            
            // Selected service chip with clear
            if (_selectedService != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedService!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _clearSelectedService,
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Radius Slider + Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Radius:',
                        style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
                      ),
                      Expanded(
                        child: Slider(
                          value: _radiusKm,
                          min: 1,
                          max: 50,
                          divisions: 49,
                          label: '${_radiusKm.toInt()} km',
                          onChanged: (value) {
                            setState(() {
                              _radiusKm = value;
                            });
                            _loadPopularServices();
                            if (_selectedService != null) {
                              _findProviders();
                            }
                          },
                        ),
                      ),
                      Text(
                        '${_radiusKm.toInt()} km',
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildFilterToggle(
                        label: 'Online only',
                        icon: Icons.wifi,
                        value: _showOnlineOnly,
                        onChanged: (val) {
                          setState(() => _showOnlineOnly = val);
                          if (_selectedService != null) _findProviders();
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildFilterToggle(
                        label: 'Premium only',
                        icon: Icons.star,
                        value: _showPremiumOnly,
                        onChanged: (val) {
                          setState(() => _showPremiumOnly = val);
                          if (_selectedService != null) _findProviders();
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _clearAllFilters,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        child: const Text(
                          'Clear all',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Results
            Expanded(
              child: _selectedService == null
                  ? const Center(
                      child: Text(
                        'Search for a service to find providers near you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
                      ),
                    )
                  : _isLoading && _providers.isEmpty
                      ? _buildSkeletonGrid(screenWidth)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                _providers.isEmpty
                                    ? 'No providers found'
                                    : '${_providers.length} provider${_providers.length > 1 ? 's' : ''} found near you',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _providers.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Text(
                                          'No providers found. Try expanding your radius or adjusting filters.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.all(16),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: aspectRatio,
                                        crossAxisSpacing: spacing,
                                        mainAxisSpacing: spacing,
                                      ),
                                      itemCount: _providers.length,
                                      itemBuilder: (context, index) {
                                        final p = _providers[index];
                                        return ProviderCard(
                                          name: p['name'],
                                          photoUrl: p['photoUrl'],
                                          isVerified: p['isVerified'],
                                          isOnline: p['isOnline'],
                                          services: List<String>.from(p['services']),
                                          rating: p['rating'],
                                          reviewCount: p['reviewCount'],
                                          distanceKm: p['distanceKm'],
                                          lastSeen: p['lastSeen'],
                                          onTap: () => _handleProviderTap(p),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToggle({
    required String label,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? AppColors.primary.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? AppColors.primary : AppColors.primary.withAlpha(30),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: value ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                color: value ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid(double screenWidth) {
    final crossAxisCount = _getCrossAxisCount(screenWidth);
    final aspectRatio = _getAspectRatio(screenWidth);
    final spacing = _getCardSpacing(screenWidth);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const ProviderCardSkeleton(),
    );
  }
}