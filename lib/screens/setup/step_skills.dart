import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../data/skills_data.dart';

class StepSkills extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onSkillsChanged;

  const StepSkills({super.key, required this.onSkillsChanged});

  @override
  State<StepSkills> createState() => _StepSkillsState();
}

class _StepSkillsState extends State<StepSkills> {
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _selectedSkills = [];
  List<Map<String, dynamic>> _allSkills = [];
  List<Map<String, dynamic>> _filteredSkills = [];
  bool _isLoading = true;
  String? _expandedCategory;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSkills() async {
    try {
      final data = await _supabase.rpc('get_all_skills');
      setState(() {
        _allSkills = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterSkills(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSkills = [];
      } else {
        _filteredSkills = _allSkills
            .where((skill) =>
                skill['name'].toString().toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleSkill(Map<String, dynamic> skill) {
    setState(() {
      final index = _selectedSkills.indexWhere((s) => s['id'] == skill['id']);
      if (index >= 0) {
        _selectedSkills.removeAt(index);
      } else {
        _selectedSkills.add(skill);
      }
      widget.onSkillsChanged(_selectedSkills);
    });
  }

  bool _isSelected(int skillId) {
    return _selectedSkills.any((s) => s['id'] == skillId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What skills do you offer?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select at least one skill',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // Search bar
              TextField(
                controller: _searchController,
                onChanged: _filterSkills,
                decoration: InputDecoration(
                  hintText: 'Search skills...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Skills list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _searchController.text.isNotEmpty
                  ? _buildSearchResults()
                  : _buildCategoryList(),
        ),

        // Selected skills
        if (_selectedSkills.isNotEmpty) _buildSelectedSkills(),
      ],
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: _filteredSkills.length,
      itemBuilder: (context, index) {
        final skill = _filteredSkills[index];
        final selected = _isSelected(skill['id']);
        return CheckboxListTile(
          value: selected,
          title: Text(
            skill['name'],
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            skill['category'],
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          onChanged: (_) => _toggleSkill(skill),
        );
      },
    );
  }

  Widget _buildCategoryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: SkillsData.categories.length,
      itemBuilder: (context, index) {
        final category = SkillsData.categories[index];
        final isExpanded = _expandedCategory == category['name'];
        final categorySkills = _allSkills
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
              ...categorySkills.map((skill) => CheckboxListTile(
                    value: _isSelected(skill['id']),
                    title: Text(
                      skill['name'],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onChanged: (_) => _toggleSkill(skill),
                  )),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _buildSelectedSkills() {
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
                'Selected (${_selectedSkills.length})',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSkills.clear();
                    widget.onSkillsChanged(_selectedSkills);
                  });
                },
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
              itemCount: _selectedSkills.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final skill = _selectedSkills[index];
                return Chip(
                  label: Text(
                    skill['name'],
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _toggleSkill(skill),
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