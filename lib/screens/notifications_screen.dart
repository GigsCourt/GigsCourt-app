import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _markAllAsRead() async {
    if (_currentUser == null) return;
    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('notifications')
        .doc(docId)
        .update({'isRead': true});
  }

  void _handleTap(Map<String, dynamic> notification, String docId) {
    _markAsRead(docId);
    final type = notification['type'] as String?;
    final referenceId = notification['referenceId'] as String?;

    switch (type) {
      case 'chat':
        if (referenceId != null) {
          Navigator.of(context).pushNamed('/chat-conversation', arguments: {
            'chatId': referenceId,
            'otherUserId': notification['senderId'] ?? '',
            'otherUserName': notification['senderName'] ?? '',
          });
        }
        break;
      case 'subscription':
        Navigator.of(context).pushNamed('/subscription');
        break;
      case 'review':
        if (referenceId != null) {
          Navigator.of(context).pushNamed('/provider-profile', arguments: referenceId);
        }
        break;
      case 'admin_service':
        Navigator.of(context).pushNamed('/admin');
        break;
      case 'admin_report':
        Navigator.of(context).pushNamed('/admin');
        break;
      case 'admin_ticket':
        Navigator.of(context).pushNamed('/admin');
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.primary),
        body: const Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Notifications',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _markAllAsRead,
            child: const Text('Mark all read',
                style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser.uid)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!.docs;

          if (notifications.isEmpty) {
            return const Center(
              child: Text('No notifications yet.',
                  style: TextStyle(
                      fontFamily: 'Inter', color: AppColors.textSecondary)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification =
                  notifications[index].data() as Map<String, dynamic>;
              final isRead = notification['isRead'] ?? false;
              final title = notification['title'] ?? '';
              final body = notification['body'] ?? '';
              final createdAt = notification['createdAt'] as Timestamp?;

              return GestureDetector(
                onTap: () => _handleTap(notification, notifications[index].id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isRead
                          ? Colors.transparent
                          : AppColors.primary.withAlpha(51),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6, right: 12),
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight:
                                        isRead ? FontWeight.w400 : FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text(body,
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Text(_formatTime(createdAt),
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final date = timestamp.toDate();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}