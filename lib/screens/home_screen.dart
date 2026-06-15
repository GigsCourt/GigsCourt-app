import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../widgets/provider_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _featuredProviders = [];
  List<Map<String, dynamic>> _allProviders = [];
  bool _isLoading = true;
  double? _userLat;
  double? _userLng;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _getLocationAndLoadProviders();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getLocationAndLoadProviders() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
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
    if (_userLat == null || _userLng == null) return;

    try {
      final nearbyData = await _supabase.rpc('find_nearby_providers', params: {
        'p_lat': _userLat,
        'p_lng': _userLng,
        'p_radius_meters': 50000,
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

      final userIds = nearbyUsers.map((p) => p['user_id'] as String).toList();

      // Batch fetch from Cloud Function
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user!.getIdToken();

      final response = await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/getProviderDetails'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'userIds': userIds}),
      );

      if (response.statusCode != 200) {
        setState(() => _isLoading = false);
        return;
      }

      final data = jsonDecode(response.body);
      final results = data['results'] as Map<String, dynamic>;

      // Combine Supabase location data with Firestore data
      final providers = nearbyUsers.map((supa) {
        final id = supa['user_id'] as String;
        final fireData = results[id] as Map<String, dynamic>?;
        final provider = fireData?['provider'] as Map<String, dynamic>?;
        final userData = fireData?['user'] as Map<String, dynamic>?;

        return {
          'userId': id,
          'name': userData?['displayName'] ?? 'Unknown',
          'photoUrl': userData?['photoUrl'],
          'isVerified': provider?['subscriptionStatus'] == 'premium',
          'isOnline': provider?['isOnline'] ?? false,
          'services': _getServiceNames(provider?['services'] ?? []),
          'rating': (provider?['averageRating'] ?? 0.0).toDouble(),
          'reviewCount': provider?['reviewCount'] ?? 0,
          'distanceKm': (supa['distance_meters'] as num) / 1000.0,
          'lastReviewedAt': provider?['lastReviewedAt'],
        };
      }).toList();

      // Sort: distance → recently reviewed → # reviews → rating
      providers.sort((a, b) {
        final distCompare = (a['distanceKm'] as double)
            .compareTo(b['distanceKm'] as double);
        if (distCompare != 0) return distCompare;

        final aLast = a['lastReviewedAt'];
        final bLast = b['lastReviewedAt'];
        if (aLast != null && bLast != null) {
          final dateCompare = (bLast as dynamic).compareTo(aLast as dynamic);
          if (dateCompare != 0) return dateCompare;
        }

        final reviewCompare = (b['reviewCount'] as int)
            .compareTo(a['reviewCount'] as int);
        if (reviewCompare != 0) return reviewCompare;

        if ((a['rating'] as double) < 3.0) return 1;
        if ((b['rating'] as double) < 3.0) return -1;
        return (b['rating'] as double).compareTo(a['rating'] as double);
      });

      setState(() {
        _featuredProviders =
            providers.where((p) => p['isVerified'] == true).toList();
        _allProviders = providers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<String> _getServiceNames(dynamic services) {
    if (services is List) {
      return services.map((s) => s.toString()).toList();
    }
    return [];
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await _loadProviders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'GigsCourt',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed('/notifications');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
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
                          final provider = _featuredProviders[index];
                          return ProviderCard(
                            name: provider['name'],
                            photoUrl: provider['photoUrl'],
                            isVerified: provider['isVerified'],
                            isOnline: provider['isOnline'],
                            services: List<String>.from(provider['services']),
                            rating: provider['rating'],
                            reviewCount: provider['reviewCount'],
                            distanceKm: provider['distanceKm'],
                            isHorizontal: true,
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                '/provider-profile',
                                arguments: provider['userId'],
                              );
                            },
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
                      child: Text(
                        'No providers found nearby.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _allProviders.length,
                      itemBuilder: (context, index) {
                        final provider = _allProviders[index];
                        return ProviderCard(
                          name: provider['name'],
                          photoUrl: provider['photoUrl'],
                          isVerified: provider['isVerified'],
                          isOnline: provider['isOnline'],
                          services: List<String>.from(provider['services']),
                          rating: provider['rating'],
                          reviewCount: provider['reviewCount'],
                          distanceKm: provider['distanceKm'],
                          onTap: () {
                            Navigator.of(context).pushNamed(
                              '/provider-profile',
                              arguments: provider['userId'],
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: AppColors.textPrimary,
      ),
    );
  }
}