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

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_notifyParent);
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
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
      _mapController.move(_currentLocation!, 16);
      _resolveAddress(_currentLocation!);
    } catch (e) {
      setState(() => _isLoadingLocation = false);
    }
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Column(
            children: [
              Text(
                'Where do you work?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set your workspace location so clients can find you',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Map
        Expanded(
          child: _isLoadingLocation
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation ?? const LatLng(9.082, 8.675),
                        initialZoom: 5.0,
                        onTap: (tapPosition, point) {
                          setState(() => _selectedLocation = point);
                          _resolveAddress(point);
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
                    // Center pin indicator when dragging
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
                  ],
                ),
        ),

        // Address input
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
          child: TextFormField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: 'Workspace address',
              hintText: 'Enter your workspace address',
              helperText: 'You can edit this address if it\'s not correct.',
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}