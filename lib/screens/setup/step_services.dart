import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../data/services_data.dart';

class StepServices extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onServicesChanged;
  final bool isOptional;

  const StepServices({
    super.key,
    required this.onServicesChanged,
    this.isOptional = false,
  });

  @override
  State<StepServices> createState() => _StepServicesState();
}

class _StepServicesState extends State<StepServices> {
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _selectedServices = [];
  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredServices = [];
  bool _isLoading = true;
  String? _expandedCategory;

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
    _loadServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final data = await _supabase.rpc('get_all_services');
      setState(() {
        _allServices = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterServices(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredServices = [];
      } else {
        _filteredServices = _allServices
            .where((service) =>
                service['name'].toString().toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleService(Map<String, dynamic> service) {
    setState(() {
      final index = _selectedServices.indexWhere((s) => s['id'] == service['id']);
      if (index >= 0) {
        _selectedServices.removeAt(index);
      } else {
        _selectedServices.add(service);
      }
      widget.onServicesChanged(_selectedServices);
    });
  }

  bool _isSelected(int serviceId) {
    return _selectedServices.any((s) => s['id'] == serviceId);
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _getFontSize(context, 16.0);
    final padding = _getPadding(context, 32.0);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What services do you offer?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize + 8,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isOptional
                    ? 'Select services you offer (optional)'
                    : 'Select at least one service',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: fontSize,
                  color: AppColors.textSecondary,
                ),
              ),
              if (widget.isOptional) ...[
                const SizedBox(height: 4),
                Text(
                  'If you don\'t select any services, you won\'t be discoverable by clients searching for your skills.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: fontSize - 2,
                    color: AppColors.accent,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                onChanged: _filterServices,
                style: TextStyle(fontSize: fontSize),
                decoration: InputDecoration(
                  hintText: 'Search services...',
                  hintStyle: TextStyle(fontSize: fontSize),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: fontSize + 4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allServices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Unable to load services. Please check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: fontSize,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : _searchController.text.isNotEmpty
                      ? _buildSearchResults(fontSize)
                      : _buildCategoryList(fontSize),
        ),

        if (_selectedServices.isNotEmpty) _buildSelectedServices(fontSize),
      ],
    );
  }

  Widget _buildSearchResults(double fontSize) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        final selected = _isSelected(service['id']);
        return CheckboxListTile(
          value: selected,
          title: Text(
            service['name'],
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: fontSize,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            service['category'],
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: fontSize - 2,
              color: AppColors.textSecondary,
            ),
          ),
          onChanged: (_) => _toggleService(service),
        );
      },
    );
  }

  Widget _buildCategoryList(double fontSize) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: ServicesData.categories.length,
      itemBuilder: (context, index) {
        final category = ServicesData.categories[index];
        final isExpanded = _expandedCategory == category['name'];
        final categoryServices = _allServices
            .where((s) => s['category'] == category['name'])
            .toList();

        return Column(
          children: [
            ListTile(
              title: Text(
                category['name']!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: AppColors.textSecondary,
              ),
              onTap: () {
                setState(() {
                  _expandedCategory =
                      isExpanded ? null : category['name'];
                });
              },
            ),
            if (isExpanded)
              ...categoryServices.map((service) => CheckboxListTile(
                    value: _isSelected(service['id']),
                    title: Text(
                      service['name'],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: fontSize,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onChanged: (_) => _toggleService(service),
                  )),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _buildSelectedServices(double fontSize) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.primary.withAlpha(26)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Selected (${_selectedServices.length})',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedServices.clear();
                    widget.onServicesChanged(_selectedServices);
                  });
                },
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: fontSize,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedServices.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final service = _selectedServices[index];
                return Chip(
                  label: Text(
                    service['name'],
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize - 2,
                    ),
                  ),
                  deleteIcon: Icon(Icons.close, size: 16),
                  onDeleted: () => _toggleService(service),
                  backgroundColor: AppColors.primary.withAlpha(20),
                  side: BorderSide.none,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}