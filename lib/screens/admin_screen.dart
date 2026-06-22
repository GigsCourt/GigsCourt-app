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
    {'title': 'Overview', 'icon': Icons.dashboard_outlined},
    {'title': 'Approvals', 'icon': Icons.checklist_outlined},
    {'title': 'Tickets', 'icon': Icons.confirmation_number_outlined},
    {'title': 'Subscriptions', 'icon': Icons.subscriptions_outlined},
    {'title': 'Users', 'icon': Icons.people_outlined},
    {'title': 'Revenue', 'icon': Icons.bar_chart_outlined},
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
        title: Text(_sections[_selectedSection]['title'] as String,
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: _buildSection(),
      bottomNavigationBar: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.primary.withAlpha(20))),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          itemCount: _sections.length,
          itemBuilder: (context, index) {
            final isSelected = _selectedSection == index;
            return GestureDetector(
              onTap: () => setState(() => _selectedSection = index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _sections[index]['icon'] as IconData,
                      size: 20,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sections[index]['title'] as String,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GridView.count(
              shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStatCard('Total Users', '${data['users']}', Icons.people),
                _buildStatCard('Subscribers', '${data['subscribers']}', Icons.verified),
                _buildStatCard('Revenue', 'NGN ${data['revenue']}', Icons.payments),
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
      return {'users': data['users'] ?? 0, 'subscribers': data['subscribers'] ?? 0, 'revenue': 0};
    }
    return {'users': 0, 'subscribers': 0, 'revenue': 0};
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withAlpha(20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.primary)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildServiceApprovals() {
    return FutureBuilder(
      future: _supabase.rpc('get_pending_services'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final services = List<Map<String, dynamic>>.from(snapshot.data);
        if (services.isEmpty) return const Center(child: Text('No pending services.', style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)));
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withAlpha(20))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(service['name'] ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_formatDate(service['created_at']), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary)),
                ])),
                IconButton(icon: const Icon(Icons.check_circle, color: AppColors.success, size: 28), onPressed: () => _approveService(service['id'])),
                IconButton(icon: const Icon(Icons.cancel, color: AppColors.error, size: 28), onPressed: () => _rejectService(service['id'])),
              ]),
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
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withAlpha(20))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withAlpha(26), borderRadius: BorderRadius.circular(4)), child: Text(type, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppColors.primary))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(data['subject'] ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14))),
                  _buildStatusBadge(data['status'] ?? 'pending'),
                ]),
                if (data['message'] != null && (data['message'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(data['message'], style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => FirebaseFirestore.instance.collection('tickets').doc(tickets[index].id).update({'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()}), child: const Text('Mark Resolved', style: TextStyle(fontSize: 13))),
              ]),
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
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withAlpha(20))),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: Text(expiry != null ? 'Expires: ${_formatDate(DateTime.parse(expiry))}' : 'Active', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                trailing: TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('users').doc(subs[index].id).update({'subscriptionStatus': 'free', 'subscriptionExpiry': null}); }, child: const Text('Revoke', style: TextStyle(color: AppColors.error, fontSize: 13))),
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
          decoration: InputDecoration(hintText: 'Search by email...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withAlpha(20))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
            Text('Est. monthly revenue: NGN ${count * 3000}', style: const TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.textSecondary)),
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
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: color)));
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    final d = DateTime.parse(date.toString());
    return '${d.day}/${d.month}/${d.year}';
  }
}