import 'package:flutter_advanced_chat_ui/flutter_advanced_chat_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Get initials from name for avatar fallback
String getInitials(String? name) {
  if (name == null || name.isEmpty) return '?';
  final parts = name.trim().split(' ');
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.substring(0, 1).toUpperCase();
}

/// Convert Firestore conversation to package Conversation model
Conversation mapToConversation({
  required String chatId,
  required Map<String, dynamic> data,
  required String currentUserId,
  required Map<String, dynamic> otherUser,
}) {
  // Build participants list — Participant requires id and displayName [citation:1]
  final participants = [
    Participant(
      id: currentUserId,
      displayName: FirebaseAuth.instance.currentUser?.displayName ?? 'You',
    ),
    Participant(
      id: otherUser['userId'] ?? '',
      displayName: otherUser['displayName'] ?? 'Unknown',
    ),
  ];

  // Build last message if exists — ChatMessage requires id, body, senderId, timestamp [citation:1]
  ChatMessage? lastMessage;
  final lastMessageText = data['lastMessage'] as String?;
  if (lastMessageText != null && lastMessageText.isNotEmpty) {
    lastMessage = ChatMessage(
      id: 'last_$chatId',
      body: lastMessageText,
      senderId: otherUser['userId'] ?? '',
      timestamp: (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  return Conversation(
    id: chatId,
    title: otherUser['displayName'] ?? 'Unknown',
    participants: participants,
    avatarUrl: otherUser['photoUrl'],
    lastMessage: lastMessage,
    unreadCount: data['unreadCount'] ?? 0,
    isTyping: data['typing_${otherUser['userId']}'] ?? false,
    settings: ConversationSettings(
      isPinned: data['isPinned'] ?? false,
      isMuted: data['isMuted'] ?? false,
    ),
  );
}

/// Convert Firestore message to package ChatMessage
ChatMessage mapToChatMessage(String messageId, Map<String, dynamic> data) {
  final type = data['type'] ?? 'text';
  
  // Determine ContentType — must use ContentType enum [citation:1]
  ContentType contentType;
  switch (type) {
    case 'photo':
      contentType = ContentType.image;
      break;
    case 'voice':
      contentType = ContentType.audio;
      break;
    default:
      contentType = ContentType.text;
  }

  // Get the body text/content
  String body;
  switch (type) {
    case 'photo':
      body = data['photoUrl'] ?? '📷 Photo';
      break;
    case 'voice':
      body = '🎤 Voice note';
      break;
    default:
      body = data['text'] ?? '';
  }

  // Determine delivery state using DeliveryState enum [citation:1]
  DeliveryState deliveryState;
  if (data['readAt'] != null) {
    deliveryState = DeliveryState.read;
  } else if (data['deliveredAt'] != null) {
    deliveryState = DeliveryState.delivered;
  } else {
    deliveryState = DeliveryState.sent;
  }

  return ChatMessage(
    id: messageId,
    body: body,
    senderId: data['senderId'] ?? '',
    timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    contentType: contentType,
    deliveryState: deliveryState,
  );
}