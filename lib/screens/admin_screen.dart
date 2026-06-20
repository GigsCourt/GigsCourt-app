import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _supabase = Supabase.instance.client;
  final _userSearchController = TextEditingController();
  int _selectedSection = 0;

  final _sections = [
    'Overview',
    'Service Approvals',
    'Tickets',
    'Subscriptions',
    'Users',
    'Revenue',
  ];

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Admin',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: Row(
        children: [
          Container(
            width: 140,
            color: AppColors.surface,
            child: ListView.builder(
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedSection == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSection = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    color: isSelected ? AppColors.primary.withAlpha(20) : Colors.transparent,
                    child: Text(_sections[index],
                        style: TextStyle(fontFamily: 'Inter', fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, fontSize: 13,
                            color: isSelected ? AppColors.primary : AppColors.textSecondary)),
                  ),
                );
              },
            ),
          ),
          Expanded(child: _buildSection()),
        ],
      ),
    );
  }

  Widget _buildSection() {
    switch (_selectedSection) {
      case 0: return _buildOverview();
      case 1: return _buildServiceApprovals();
      case 2: return _buildTickets();
      case 3: return _buildSubscriptions();
      case 4: return _buildUsers();
      case 5: return _buildRevenue();
      default: return const SizedBox();
    }
  }

  Widget _buildOverview() {
    return FutureBuilder(
      future: _loadOverview(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dashboard', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6,
              children: [
                _buildStatCard('Total Users', '${data['users']}'),
                _buildStatCard('Subscribers', '${data['subscribers']}'),
                _buildStatCard('Revenue', 'NGN ${data['revenue']}'),
              ],
            ),
          ]),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadOverview() async {
    final doc = await FirebaseFirestore.instance.collection('stats').doc('counts').get();
    if (doc.exists) {
      final data = doc.data()!;
      return {
        'users': data['users'] ?? 0,
        'subscribers': data['subscribers'] ?? 0,
        'revenue': 0,
      };
    }
    return {'users': 0, 'subscribers': 0, 'revenue': 0};
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withAlpha(26))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 24, color: AppColors.primary)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildServiceApprovals() {
    return FutureBuilder(
      future: _supabase.rpc('get_pending_services'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final services = List<Map<String, dynamic>>.from(snapshot.data);
        if (services.isEmpty) return const Center(child: Text('No pending services to review.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)));
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            return Card(
              color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(service['name'] ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                    Text('Suggested on ${_formatDate(service['created_at'])}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                  ])),
                  IconButton(icon: const Icon(Icons.check_circle, color: AppColors.success), onPressed: () => _approveService(service['id'])),
                  IconButton(icon: const Icon(Icons.cancel, color: AppColors.error), onPressed: () => _rejectService(service['id'])),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approveService(int id) async {
    await _supabase.rpc('approve_service', params: {'p_pending_id': id});
    setState(() {});
  }

  Future<void> _rejectService(int id) async {
    await _supabase.rpc('reject_service', params: {'p_pending_id': id});
    setState(() {});
  }

  Widget _buildTickets() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tickets').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tickets = snapshot.data!.docs;
        if (tickets.isEmpty) return const Center(child: Text('No tickets.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)));
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: tickets.length,
          itemBuilder: (context, index) {
            final data = tickets[index].data() as Map<String, dynamic>;
            final type = data['type'] ?? 'report';
            return Card(
              color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary.withAlpha(26), borderRadius: BorderRadius.circular(4)),
                      child: Text(type, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(data['subject'] ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600))),
                    _buildStatusBadge(data['status'] ?? 'pending'),
                  ]),
                  if (data['message'] != null && (data['message'] as String).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(data['message'], style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => FirebaseFirestore.instance.collection('tickets').doc(tickets[index].id).update({'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()}),
                    child: const Text('Mark Resolved'),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSubscriptions() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('subscriptionStatus', isEqualTo: 'premium').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final subs = snapshot.data!.docs;
        if (subs.isEmpty) return const Center(child: Text('No active subscriptions.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)));
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: subs.length,
          itemBuilder: (context, index) {
            final data = subs[index].data() as Map<String, dynamic>;
            final name = data['displayName'] ?? 'Unknown';
            final expiry = data['subscriptionExpiry'] as String?;
            return Card(
              color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: Text(expiry != null ? 'Expires: ${_formatDate(DateTime.parse(expiry))}' : 'Active', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                trailing: TextButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('users').doc(subs[index].id).update({'subscriptionStatus': 'free', 'subscriptionExpiry': null});
                  },
                  child: const Text('Revoke', style: TextStyle(color: AppColors.error)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUsers() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _userSearchController,
          decoration: InputDecoration(hintText: 'Search by email...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          onSubmitted: (value) => setState(() {}),
        ),
      ),
      Expanded(
        child: _userSearchController.text.isEmpty
            ? const Center(child: Text('Search for a user by email.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)))
            : FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('users').where('email', isEqualTo: _userSearchController.text.trim()).get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final users = snapshot.data!.docs;
                  if (users.isEmpty) return const Center(child: Text('No user found.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)));
                  return ListView.builder(
                    padding: const EdgeInsets.all(16), itemCount: users.length,
                    itemBuilder: (context, index) {
                      final data = users[index].data() as Map<String, dynamic>;
                      return Card(
                        color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(data['displayName'] ?? 'Unknown', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                          subtitle: Text(data['email'] ?? '', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildRevenue() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('users').where('subscriptionStatus', isEqualTo: 'premium').get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final count = snapshot.data!.docs.length;
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$count active subscribers', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 24, color: AppColors.primary)),
            const SizedBox(height: 8),
            Text('Estimated monthly revenue: NGN ${count * 3000}', style: const TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.textSecondary)),
          ]),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'pending': color = AppColors.accent;
      case 'dismissed': color = AppColors.textSecondary;
      case 'warned': color = AppColors.accent;
      case 'suspended': color = AppColors.error;
      case 'open': color = AppColors.accent;
      case 'resolved': color = AppColors.success;
      default: color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: color)),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    final d = DateTime.parse(date.toString());
    return '${d.day}/${d.month}/${d.year}';
  }
}