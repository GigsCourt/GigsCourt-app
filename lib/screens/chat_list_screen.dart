import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  final Map<String, Map<String, dynamic>> _userCache = {};

  Future<Map<String, Map<String, dynamic>>> _fetchUsers(List<String> userIds) async {
    final uncached = userIds.where((id) => !_userCache.containsKey(id)).toList();
    if (uncached.isEmpty) return _userCache;

    try {
      final idToken = await _currentUser!.getIdToken();
      final response = await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/getProviderDetails'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'userIds': uncached}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as Map<String, dynamic>;
        for (final id in uncached) {
          final fireData = results[id] as Map<String, dynamic>?;
          final userData = fireData?['user'] as Map<String, dynamic>?;
          if (userData != null) {
            _userCache[id] = userData;
          }
        }
      }
    } catch (_) {}

    return _userCache;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please log in'));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Chat',
            style:
                TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: _currentUser.uid)
            .orderBy('lastMessageAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data!.docs;

          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No messages yet.\nFind a provider and start chatting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Inter', color: AppColors.textSecondary),
              ),
            );
          }

          // Collect all other user IDs
          final otherUserIds = <String>{};
          for (final chat in chats) {
            final data = chat.data() as Map<String, dynamic>;
            final participants = List<String>.from(data['participants'] ?? []);
            final otherId = participants.firstWhere(
              (id) => id != _currentUser.uid,
              orElse: () => '',
            );
            if (otherId.isNotEmpty) otherUserIds.add(otherId);
          }

          // Fetch all users in one batch
          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _fetchUsers(otherUserIds.toList()),
            builder: (context, userSnapshot) {
              final users = userSnapshot.data ?? {};

              return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index].data() as Map<String, dynamic>;
                  final participants =
                      List<String>.from(chat['participants'] ?? []);
                  final otherUserId = participants.firstWhere(
                    (id) => id != _currentUser.uid,
                    orElse: () => '',
                  );
                  final userData = users[otherUserId];
                  final name = userData?['displayName'] ?? 'Unknown';
                  final photoUrl = userData?['photoUrl'];
                  final lastMessage = chat['lastMessage'] ?? '';
                  final lastMessageAt = chat['lastMessageAt'] as Timestamp?;

                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: photoUrl != null
                            ? Image.network(
                                ImageOptimizer.thumbnail(photoUrl),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppColors.primary.withAlpha(26),
                                child: Icon(Icons.person,
                                    color: AppColors.primary),
                              ),
                      ),
                    ),
                    title: Text(name,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter', color: AppColors.textSecondary),
                    ),
                    trailing: Text(
                      _formatTime(lastMessageAt),
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/chat-conversation',
                        arguments: {
                          'chatId': chats[index].id,
                          'otherUserId': otherUserId,
                          'otherUserName': name,
                        },
                      );
                    },
                  );
                },
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
    if (date.day == now.day) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }
}