import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../theme/app_theme.dart';

class StepAddress extends StatefulWidget {
  final TextEditingController addressController;
  final Function(LatLng location, String address) onAddressChanged;
  final bool isOptional;

  const StepAddress({
    super.key,
    required this.addressController,
    required this.onAddressChanged,
    this.isOptional = false,
  });

  @override
  State<StepAddress> createState() => _StepAddressState();
}

class _StepAddressState extends State<StepAddress> {
  LatLng? _currentLocation;
  bool _isLoadingLocation = true;
  bool _isResolvingAddress = false;
  GoogleMapController? _mapController;
  Timer? _debounceTimer;
  LatLng? _lastCameraPosition;

  // ========== RESPONSIVE HELPERS ==========

  double _getFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return baseSize * 0.85;
    if (screenWidth > 600) return baseSize * 1.1;
    return baseSize;
  }

  double _getPadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) return basePadding * 0.8;
    if (screenWidth > 600) return basePadding * 1.2;
    return basePadding;
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });
      _moveMap(_currentLocation!);
      _resolveAddress(_currentLocation!);
    } catch (e) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _moveMap(LatLng location) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: location,
            zoom: 14,
          ),
        ),
      );
    }
  }

  void _onMapChanged(LatLng point) {
    setState(() => _currentLocation = point);
    widget.onAddressChanged(point, widget.addressController.text);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
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
        widget.addressController.text = address;
        widget.onAddressChanged(location, address);
      }
    } catch (e) {
      // Address resolution failed, user can type manually
    }
    if (mounted) setState(() => _isResolvingAddress = false);
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(context, 16.0);
    final padding = _getPadding(context, 16.0);
    final titleSize = _getFontSize(context, 24.0);

    if (_isLoadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: (controller) {
            _mapController = controller;
            if (_currentLocation != null) {
              _moveMap(_currentLocation!);
            }
          },
          initialCameraPosition: CameraPosition(
            target: _currentLocation ?? const LatLng(9.082, 8.675),
            zoom: 14,
          ),
          onTap: (point) => _onMapChanged(point),
          onCameraMove: (position) {
            _lastCameraPosition = position.target;
          },
          onCameraIdle: () {
            if (_lastCameraPosition != null) {
              _onMapChanged(_lastCameraPosition!);
            }
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapType: MapType.normal,
        ),

        IgnorePointer(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_pin,
                  color: AppColors.primary,
                  size: 48,
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

        Positioned(
          left: padding,
          right: padding,
          bottom: padding + 60,
          child: Container(
            padding: EdgeInsets.all(padding),
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
                    fontSize: titleSize,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Drag the map to set your workspace',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: fontSize,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: widget.addressController,
                  style: TextStyle(fontSize: fontSize),
                  decoration: InputDecoration(
                    labelText: widget.isOptional ? 'Workspace address (Optional)' : 'Workspace address',
                    hintText: 'Enter your workspace address',
                    helperText: widget.isOptional
                        ? 'If you don\'t add your workspace address, you won\'t be discoverable by clients nearby.'
                        : 'You can edit if incorrect',
                    helperMaxLines: 2,
                    labelStyle: TextStyle(fontSize: fontSize),
                    hintStyle: TextStyle(fontSize: fontSize),
                    helperStyle: TextStyle(
                      fontSize: fontSize - 2,
                      color: widget.isOptional ? AppColors.accent : AppColors.textSecondary,
                    ),
                    suffixIcon: _isResolvingAddress
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: fontSize + 4,
                    ),
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