import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../theme/app_theme.dart';

class StepAddress extends StatefulWidget {
  final Function(LatLng location, String address) onAddressChanged;

  const StepAddress({super.key, required this.onAddressChanged});

  @override
  State<StepAddress> createState() => _StepAddressState();
}

class _StepAddressState extends State<StepAddress> {
  final _addressController = TextEditingController();
  LatLng? _currentLocation;
  LatLng? _selectedLocation;
  bool _isLoadingLocation = true;
  bool _isResolvingAddress = false;
  final MapController _mapController = MapController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_notifyParent);
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _notifyParent() {
    if (_selectedLocation != null && _addressController.text.isNotEmpty) {
      widget.onAddressChanged(_selectedLocation!, _addressController.text);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _selectedLocation = _currentLocation;
        _isLoadingLocation = false;
      });
      _mapController.move(_currentLocation!, 14);
      _resolveAddress(_currentLocation!);
    } catch (e) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onMapChanged(LatLng point) {
    setState(() => _selectedLocation = point);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _resolveAddress(point);
    });
  }

  Future<void> _resolveAddress(LatLng location) async {
    setState(() => _isResolvingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final address = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}'
            .trim()
            .replaceAll(RegExp(r'^,\s*|,\s*$|,\s*,+'), '');
        _addressController.text = address;
        _notifyParent();
      }
    } catch (e) {
      // Address resolution failed, user can type manually
    }
    if (mounted) setState(() => _isResolvingAddress = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation ?? const LatLng(9.082, 8.675),
            initialZoom: 14.0,
            onTap: (tapPosition, point) => _onMapChanged(point),
            onMapEvent: (event) {
              if (event is MapEventMoveEnd) {
                final center = _mapController.camera.center;
                _onMapChanged(center);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.gigscourt',
            ),
            if (_selectedLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_pin,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ],
              ),
          ],
        ),

        IgnorePointer(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_pin,
                  color: AppColors.primary,
                  size: 40,
                ),
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Smaller overlay at bottom
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where do you work?',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Drag the map to set your workspace',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Workspace address',
                    hintText: 'Enter your workspace address',
                    helperText: 'You can edit if incorrect',
                    helperMaxLines: 1,
                    suffixIcon: _isResolvingAddress
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}