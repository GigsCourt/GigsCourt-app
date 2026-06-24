import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  // Search
  String _searchQuery = '';

  // ========== PAGINATION ==========
  DocumentSnapshot? _lastDocument;
  bool _hasMoreChats = true;
  bool _isLoadingMore = false;
  final int _pageSize = 20;

  // ========== SCROLL CONTROLLER ==========
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (currentScroll >= maxScroll - 100 && _hasMoreChats && !_isLoadingMore) {
        _loadMoreChats();
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchUsers(List<String> userIds) async {
    final uncached = userIds.where((id) => !_userCache.containsKey(id)).toList();
    if (uncached.isEmpty) return _userCache;

    final futures = uncached.map((id) => 
      FirebaseFirestore.instance.collection('users').doc(id).get()
    ).toList();
    
    final docs = await Future.wait(futures);
    
    for (int i = 0; i < uncached.length; i++) {
      final doc = docs[i];
      if (doc.exists) {
        _userCache[uncached[i]] = doc.data()!;
      }
    }

    return _userCache;
  }

  Future<void> _loadMoreChats() async {
    if (_isLoadingMore || !_hasMoreChats) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      Query query = FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _currentUser!.uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(_pageSize);
      
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      
      final snapshot = await query.get();
      
      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMoreChats = false;
          _isLoadingMore = false;
        });
        return;
      }
      
      setState(() {
        _lastDocument = snapshot.docs.last;
        _isLoadingMore = false;
      });
      
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
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
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // ========== SEARCH BAR ==========
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          // ========== CHAT LIST ==========
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: _currentUser.uid)
                  .orderBy('lastMessageAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var chats = snapshot.data!.docs;

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

                return FutureBuilder<Map<String, Map<String, dynamic>>>(
                  future: _fetchUsers(otherUserIds.toList()),
                  builder: (context, userSnapshot) {
                    final users = userSnapshot.data ?? {};

                    // Filter chats by search query
                    if (_searchQuery.isNotEmpty) {
                      chats = chats.where((chat) {
                        final data = chat.data() as Map<String, dynamic>;
                        final participants = List<String>.from(data['participants'] ?? []);
                        final otherId = participants.firstWhere(
                          (id) => id != _currentUser.uid,
                          orElse: () => '',
                        );
                        final userData = users[otherId];
                        final name = userData?['displayName'] ?? 'Unknown';
                        return name.toLowerCase().contains(_searchQuery);
                      }).toList();
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index].data() as Map<String, dynamic>;
                        final participants = List<String>.from(chat['participants'] ?? []);
                        final otherUserId = participants.firstWhere(
                          (id) => id != _currentUser.uid,
                          orElse: () => '',
                        );
                        final userData = users[otherUserId];
                        final name = userData?['displayName'] ?? 'Unknown';
                        final photoUrl = userData?['photoUrl'];
                        final lastMessage = chat['lastMessage'] ?? '';
                        final lastMessageAt = chat['lastMessageAt'] as Timestamp?;
                        final unreadCount = chat['unreadCount'] ?? 0;
                        final isTyping = chat['typing_${otherUserId}'] ?? false;
                        
                        // ========== ONLINE STATUS ==========
                        final isOnline = userData?['isOnline'] ?? false;

                        return GestureDetector(
                          onLongPress: () {
                            _showChatMenu(chat, otherUserId, name);
                          },
                          child: ListTile(
                            leading: Stack(
                              children: [
                                ClipRRect(
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
                                // ========== ONLINE / OFFLINE INDICATOR ==========
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: isOnline ? AppColors.success : AppColors.textSecondary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              isTyping ? 'Typing...' : lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: isTyping ? AppColors.primary : AppColors.textSecondary,
                                  fontWeight: isTyping ? FontWeight.w600 : FontWeight.w400),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(lastMessageAt),
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
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
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ========== LONG-PRESS MENU ==========
  void _showChatMenu(Map<String, dynamic> chat, String otherUserId, String otherUserName) {
    final chatId = chat['id'] as String? ?? '';
    final isPinned = chat['isPinned'] ?? false;
    final isMuted = chat['isMuted'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: AppColors.primary,
                ),
                title: Text(
                  isPinned ? 'Unpin' : 'Pin',
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _togglePinned(chatId, !isPinned);
                },
              ),
              ListTile(
                leading: Icon(
                  isMuted ? Icons.volume_up : Icons.volume_off,
                  color: AppColors.primary,
                ),
                title: Text(
                  isMuted ? 'Unmute' : 'Mute',
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleMuted(chatId, !isMuted);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteChat(chatId, otherUserName);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ========== PIN ==========
  Future<void> _togglePinned(String chatId, bool isPinned) async {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'isPinned': isPinned,
    });
  }

  // ========== MUTE ==========
  Future<void> _toggleMuted(String chatId, bool isMuted) async {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'isMuted': isMuted,
    });
  }

  // ========== DELETE ==========
  Future<void> _confirmDeleteChat(String chatId, String otherUserName) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete Conversation',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Delete conversation with $otherUserName?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteChat(chatId);
            },
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChat(String chatId) async {
    try {
      final messages = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(FirebaseFirestore.instance.collection('chats').doc(chatId));
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete conversation.')),
        );
      }
    }
  }

  // ========== FORMAT TIME ==========
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