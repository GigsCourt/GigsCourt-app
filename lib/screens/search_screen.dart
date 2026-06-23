import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
  final MapController _mapController = MapController();
  final _remoteConfig = FirebaseRemoteConfig.instance;

  bool _isMapView = true;
  bool _isLoading = false;
  bool _isEarlyAccess = false;
  double _radiusKm = 10;
  double? _userLat;
  double? _userLng;
  String? _selectedService;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _providers = [];

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !_remoteConfig.getBool('subscriptions_enforced');
    _getLocation();
    _loadAllServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllServices() async {
    try {
      final data = await _supabase.rpc('get_all_services');
      setState(() {
        _services = List<Map<String, dynamic>>.from(data);
      });
    } catch (_) {}
  }

  Future<void> _getLocation() async {
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
    } catch (_) {}
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

      final filtered = providersRaw
          .where((p) => (p['serviceIds'] as List<int>).contains(serviceId))
          .toList();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
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
                      suffixIcon: IconButton(
                        icon: Icon(_isMapView ? Icons.list : Icons.map),
                        onPressed: () => setState(() => _isMapView = !_isMapView),
                      ),
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
                          BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 8, offset: const Offset(0, 2)),
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
                            title: Text(service['name'], style: const TextStyle(fontFamily: 'Inter')),
                            subtitle: Text(service['category'], style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
                            onTap: () => _selectService(service),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_selectedService != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('Radius:', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
                    Expanded(
                      child: Slider(
                        value: _radiusKm, min: 1, max: 50, divisions: 49,
                        label: '${_radiusKm.toInt()} km',
                        onChanged: (value) {
                          setState(() => _radiusKm = value);
                          _findProviders();
                        },
                      ),
                    ),
                    Text('${_radiusKm.toInt()} km', style: const TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
                  ],
                ),
              ),
            Expanded(
              child: _selectedService == null
                  ? const Center(
                      child: Text('Search for a service to find providers near you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
                    )
                  : _isLoading && _providers.isEmpty
                      ? _buildSkeletonGrid()
                      : _isMapView
                          ? _buildMapView()
                          : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: 6,
      itemBuilder: (_, _) => const ProviderCardSkeleton(),
    );
  }

  Widget _buildMapView() {
    if (_userLat == null || _userLng == null) return const Center(child: CircularProgressIndicator());

    final points = <Map<String, dynamic>>[];
    for (final p in _providers) {
      final lat = p['latitude'] as double?;
      final lng = p['longitude'] as double?;
      if (lat != null && lng != null) {
        points.add({'lat': lat, 'lng': lng, 'provider': p});
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(_userLat!, _userLng!),
        initialZoom: _radiusToZoom(_radiusKm),
        onMapEvent: (event) => setState(() {}),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.gigscourt',
        ),
        MarkerLayer(markers: _buildClusteredMarkers(points)),
      ],
    );
  }

  List<Marker> _buildClusteredMarkers(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return [];

    final zoom = _mapController.camera.zoom;
    final markers = <Marker>[];

    if (zoom >= 14 || points.length <= 3) {
      for (final point in points) {
        final p = point['provider'] as Map<String, dynamic>;
        markers.add(Marker(
          point: LatLng(point['lat'] as double, point['lng'] as double),
          width: 36, height: 36,
          child: GestureDetector(
            onTap: () => _handleProviderTap(p),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p['isOnline'] == true ? AppColors.success : Colors.transparent,
                  width: 3,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: p['photoUrl'] != null
                    ? Image.network(p['photoUrl'], width: 30, height: 30, fit: BoxFit.cover)
                    : Container(
                        width: 30, height: 30,
                        color: AppColors.primary.withAlpha(51),
                        child: Icon(Icons.person, size: 16, color: AppColors.primary),
                      ),
              ),
            ),
          ),
        ));
      }
    } else {
      final clusterRadius = _getClusterRadius(zoom);
      final clusters = <String, List<Map<String, dynamic>>>{};

      for (final point in points) {
        final lat = point['lat'] as double;
final lng = point['lng'] as double;
final latKey = (lat / clusterRadius).round();
final lngKey = (lng / clusterRadius).round();
        final key = '$latKey,$lngKey';
        clusters.putIfAbsent(key, () => []);
        clusters[key]!.add(point);
      }

      for (final entry in clusters.entries) {
        final clusterPoints = entry.value;
        if (clusterPoints.length == 1) {
          final p = clusterPoints.first['provider'] as Map<String, dynamic>;
          markers.add(Marker(
            point: LatLng(clusterPoints.first['lat'] as double, clusterPoints.first['lng'] as double),
            width: 36, height: 36,
            child: GestureDetector(
              onTap: () => _handleProviderTap(p),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: p['isOnline'] == true ? AppColors.success : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: p['photoUrl'] != null
                      ? Image.network(p['photoUrl'], width: 30, height: 30, fit: BoxFit.cover)
                      : Container(
                          width: 30, height: 30,
                          color: AppColors.primary.withAlpha(51),
                          child: Icon(Icons.person, size: 16, color: AppColors.primary),
                        ),
                ),
              ),
            ),
          ));
        } else {
          final avgLat = clusterPoints.map((p) => p['lat'] as double).reduce((a, b) => a + b) / clusterPoints.length;
          final avgLng = clusterPoints.map((p) => p['lng'] as double).reduce((a, b) => a + b) / clusterPoints.length;
          markers.add(Marker(
            point: LatLng(avgLat, avgLng),
            width: 44, height: 44,
            child: GestureDetector(
              onTap: () => _mapController.move(LatLng(avgLat, avgLng), zoom + 2),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                child: Center(
                  child: Text(
                    '${clusterPoints.length}',
                    style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ));
        }
      }
    }
    return markers;
  }

  double _getClusterRadius(double zoom) {
    if (zoom <= 8) return 2.0;
    if (zoom <= 10) return 1.0;
    if (zoom <= 12) return 0.5;
    return 0.1;
  }

  Widget _buildListView() {
    if (_providers.isEmpty) {
      return const Center(
        child: Text('No providers found. Try expanding your radius.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
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
    );
  }

  double _radiusToZoom(double radiusKm) {
    if (radiusKm <= 2) return 15;
    if (radiusKm <= 5) return 14;
    if (radiusKm <= 10) return 13;
    if (radiusKm <= 20) return 12;
    if (radiusKm <= 30) return 11;
    return 10;
  }
}