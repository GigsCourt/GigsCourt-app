import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_advanced_chat_ui/flutter_advanced_chat_ui.dart';
import '../models/chat_models.dart';

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get conversations as a list (for the controller)
  Future<List<Conversation>> fetchConversations(String userId) async {
    final snapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .get();

    if (snapshot.docs.isEmpty) return [];

    // Fetch all other users' data
    final userIds = <String>[];
    final userMap = <String, Map<String, dynamic>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      final otherId = participants.firstWhere((id) => id != userId);
      if (!userMap.containsKey(otherId)) {
        userIds.add(otherId);
      }
    }

    if (userIds.isNotEmpty) {
      final userDocs = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();
      for (final doc in userDocs.docs) {
        userMap[doc.id] = doc.data();
      }
    }

    // Build conversations
    final conversations = <Conversation>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      final otherId = participants.firstWhere((id) => id != userId);
      final otherUser = userMap[otherId] ?? {};

      final conversation = mapToConversation(
        chatId: doc.id,
        data: data,
        currentUserId: userId,
        otherUser: {
          'userId': otherId,
          ...otherUser,
        },
      );
      conversations.add(conversation);
    }

    return conversations;
  }

  /// Get messages as a list (for the controller)
  Future<List<ChatMessage>> fetchMessages(String chatId) async {
    final snapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) {
      return mapToChatMessage(doc.id, doc.data());
    }).toList();
  }

  /// Send a message
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    String? photoUrl,
    String? voiceUrl,
    int? voiceDuration,
  }) async {
    String type = 'text';
    if (photoUrl != null) type = 'photo';
    if (voiceUrl != null) type = 'voice';

    final messageData = {
      'senderId': senderId,
      'text': text,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
      'deliveredAt': FieldValue.serverTimestamp(),
    };

    if (photoUrl != null) messageData['photoUrl'] = photoUrl;
    if (voiceUrl != null) {
      messageData['voiceUrl'] = voiceUrl;
      messageData['voiceDuration'] = voiceDuration;
    }

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);

    String lastMessage = text;
    if (photoUrl != null) lastMessage = '📷 Photo';
    if (voiceUrl != null) lastMessage = '🎤 Voice note';

    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark messages as read
  Future<void> markAsRead(String chatId, String otherUserId) async {
    final unread = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: otherUserId)
        .where('readAt', isEqualTo: null)
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  /// Listen to new messages in real-time
  Stream<ChatMessage> listenForNewMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return mapToChatMessage(snapshot.docs.first.id, snapshot.docs.first.data());
        })
        .where((message) => message != null)
        .map((message) => message!);
  }
}