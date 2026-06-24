import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';
import '../services/imagekit_service.dart';

class ChatConversationScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;

  const ChatConversationScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isUploading = false;
  bool _isRecording = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  String? _playingVoiceUrl;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;

  // Reply to message
  String? _replyToMessageId;
  String? _replyToText;
  bool _isReplying = false;

  // Online status
  bool _isOtherOnline = false;

  // Emoji reactions
  final List<String> _availableEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  // ========== PAGINATION VARIABLES ==========
  DocumentSnapshot? _lastDocument;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  final int _pageSize = 30;
  bool _isInitialLoad = true;

  // ========== SCROLL TO BOTTOM ==========
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _listenToTyping();
    _markMessagesAsRead();
    _listenToOnlineStatus();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      // Show/hide scroll to bottom button
      setState(() {
        _showScrollToBottom = _scrollController.offset < -200;
      });

      // Check if scrolled to top for pagination
      if (_scrollController.position.pixels <= 0 && _hasMoreMessages && !_isLoadingMore) {
        _loadMoreMessages();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _listenToTyping() {
    _messageController.addListener(() {
      if (_messageController.text.isNotEmpty && !_isTyping) {
        _setTyping(true);
      } else if (_messageController.text.isEmpty && _isTyping) {
        _setTyping(false);
      }
    });
  }

  Future<void> _setTyping(bool value) async {
    _isTyping = value;
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'typing_${_currentUser!.uid}': value,
    });
    if (value) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_isTyping) _setTyping(false);
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    final unreadMessages = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).collection('messages')
        .where('senderId', isEqualTo: widget.otherUserId)
        .where('readAt', isEqualTo: null).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  void _listenToOnlineStatus() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final isOnline = data['isOnline'] ?? false;
        if (_isOtherOnline != isOnline) {
          setState(() => _isOtherOnline = isOnline);
        }
      }
    });
  }

  // ========== SEND MESSAGE ==========

  Future<void> _sendMessage({String? text, String? photoUrl, String? voiceUrl, int? voiceDuration}) async {
    if (_currentUser == null) return;
    if (text == null && photoUrl == null && voiceUrl == null) return;
    if (text != null) {
      _messageController.clear();
      _setTyping(false);
    }
    String type = 'text';
    if (photoUrl != null) type = 'photo';
    if (voiceUrl != null) type = 'voice';

    final messageData = {
      'senderId': _currentUser.uid,
      'text': text ?? '',
      'photoUrl': photoUrl,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
      'replyTo': _replyToMessageId,
    };
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add(messageData);

    String lastMessage = text ?? '';
    if (photoUrl != null) lastMessage = '📷 Photo';
    if (voiceUrl != null) lastMessage = '🎤 Voice note';
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    _cancelReply();
    _scrollToBottom();
  }

  // ========== REPLY TO MESSAGES ==========

  void _startReply(String messageId, String messageText) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToText = messageText;
      _isReplying = true;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyToMessageId = null;
      _replyToText = null;
      _isReplying = false;
    });
  }

  // ========== PHOTO MESSAGES ==========

  Future<void> _pickAndSendPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _isUploading = true);
    final result = await ImageKitService.uploadImage(File(picked.path), 'chat_${DateTime.now().millisecondsSinceEpoch}');
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        await _sendMessage(photoUrl: result['url']);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send photo.')));
        }
      }
    }
  }

  // ========== VOICE MESSAGES ==========

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required.')));
      }
      return;
    }
    setState(() => _isRecording = true);
    final tempDir = Directory.systemTemp;
    final filePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050), path: filePath);
  }

  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;

    setState(() => _isUploading = true);
    final result = await ImageKitService.uploadImage(
      File(path),
      'voice_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        final file = File(path);
        final fileSize = await file.length();
        final estimatedSeconds = (fileSize / 8000).round();
        await _sendMessage(voiceUrl: result['url'], voiceDuration: estimatedSeconds);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send voice note.')),
          );
        }
      }
    }
  }

  // ========== VOICE PLAYBACK ==========

  Future<void> _playVoice(String url) async {
    if (_isPlaying && _playingVoiceUrl == url) {
      await _audioPlayer.pause();
    } else if (_playingVoiceUrl == url && !_isPlaying) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      _playingVoiceUrl = url;
    }
    await _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  void _cycleSpeed() {
    setState(() {
      if (_playbackSpeed >= 2.0) {
        _playbackSpeed = 0.5;
      } else if (_playbackSpeed >= 1.5) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed >= 1.0) {
        _playbackSpeed = 1.5;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  // ========== EMOJI REACTIONS ==========

  Future<void> _addReaction(String messageId, String emoji) async {
    final messageRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId);
    
    await messageRef.update({
      'reactions': FieldValue.arrayUnion([emoji]),
    });
  }

  Future<void> _removeReaction(String messageId, String emoji) async {
    final messageRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId);
    
    await messageRef.update({
      'reactions': FieldValue.arrayRemove([emoji]),
    });
  }

  // ========== EDIT MESSAGE ==========

  Future<void> _editMessage(String messageId, String currentText) async {
    final controller = TextEditingController(text: currentText);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Edit Message', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save', style: TextStyle(fontFamily: 'Inter', color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'text': controller.text.trim(),
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ========== DELETE MESSAGE ==========

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Message', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        content: const Text('Delete this message for everyone?', style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    }
  }

  // ========== REVIEW SYSTEM ==========

  Future<void> _showReviewDialog() async {
    int rating = 0;
    final commentController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Rate & Review', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(
              icon: Icon(index < rating ? Icons.star : Icons.star_border, color: AppColors.accent, size: 36),
              onPressed: () => setDialogState(() => rating = index + 1),
            ))),
            const SizedBox(height: 12),
            TextField(controller: commentController, maxLines: 3, decoration: InputDecoration(hintText: 'Share your experience (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter'))),
            TextButton(onPressed: () { if (rating > 0) Navigator.pop(ctx, true); }, child: const Text('Submit', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );

    if (result == true && rating > 0) {
      final existingReview = await FirebaseFirestore.instance.collection('reviews')
          .where('providerId', isEqualTo: widget.otherUserId)
          .where('clientId', isEqualTo: _currentUser!.uid).get();
      if (existingReview.docs.isNotEmpty) {
        await existingReview.docs.first.reference.update({'rating': rating, 'comment': commentController.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await FirebaseFirestore.instance.collection('reviews').add({
          'providerId': widget.otherUserId, 'clientId': _currentUser.uid, 'rating': rating, 'comment': commentController.text.trim(), 'createdAt': FieldValue.serverTimestamp(),
        });
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final idToken = await user.getIdToken();
            await http.post(Uri.parse('https://us-central1-gigs-court.cloudfunctions.net/trackEngagement'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
              body: jsonEncode({'providerId': widget.otherUserId, 'type': 'review'}));
          }
        } catch (_) {}
      }
      final allReviews = await FirebaseFirestore.instance.collection('reviews').where('providerId', isEqualTo: widget.otherUserId).get();
      double totalRating = 0;
      for (final doc in allReviews.docs) { totalRating += (doc.data()['rating'] as num).toDouble(); }
      final avgRating = allReviews.docs.isEmpty ? 0.0 : totalRating / allReviews.docs.length;
      await FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).update({'averageRating': avgRating, 'reviewCount': allReviews.docs.length, 'lastReviewedAt': FieldValue.serverTimestamp()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review submitted. Thank you!')));
    }
  }

  // ========== SHOW MESSAGE MENU ==========

  void _showMessageMenu({
    required String messageId,
    required String messageText,
    required String messageType,
    required List<String> reactions,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji reactions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _availableEmojis.map((emoji) {
                    final isReacted = reactions.contains(emoji);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        if (isReacted) {
                          _removeReaction(messageId, emoji);
                        } else {
                          _addReaction(messageId, emoji);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isReacted ? AppColors.primary.withAlpha(20) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          emoji,
                          style: TextStyle(
                            fontSize: 28,
                            color: isReacted ? null : Colors.black.withAlpha(100),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              // Menu options
              ListTile(
                leading: const Icon(Icons.reply, color: AppColors.primary),
                title: const Text('Reply', style: TextStyle(fontFamily: 'Inter')),
                onTap: () {
                  Navigator.pop(ctx);
                  _startReply(messageId, messageText);
                },
              ),
              if (messageType != 'voice' && messageType != 'photo') ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: AppColors.primary),
                  title: const Text('Edit', style: TextStyle(fontFamily: 'Inter')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(messageId, messageText);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(messageId);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ========== UTILITIES ==========

  String _formatMessageTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ========== MESSAGE GROUPING ==========

  String _getMessageGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);
    
    final difference = today.difference(messageDate).inDays;
    
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return 'This Week';
    if (difference < 30) return 'This Month';
    return 'Older';
  }

  // ========== RESPONSIVE HELPERS ==========

  double _getMaxMessageWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) {
      return screenWidth * 0.80;
    } else if (screenWidth < 600) {
      return screenWidth * 0.75;
    } else {
      return screenWidth * 0.60;
    }
  }

  double _getFontSize(double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 380) {
      return baseSize * 0.9;
    } else if (screenWidth > 500) {
      return baseSize * 1.1;
    }
    return baseSize;
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    final maxWidth = _getMaxMessageWidth(context);
    final fontSize = _getFontSize(13.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Row(
          children: [
            // Online status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _isOtherOnline ? AppColors.success : AppColors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                    return Text(
                      data?['typing_${widget.otherUserId}'] == true ? 'typing...' : '',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: 'Rate & Review',
            onPressed: _showReviewDialog,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .limit(_pageSize)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      final messages = snapshot.data!.docs;
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text(
                            'No messages yet. Say hello!',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      }

                      // Store last document for pagination
                      if (messages.isNotEmpty && _isInitialLoad) {
                        _lastDocument = messages.last;
                        _isInitialLoad = false;
                      }

                      // Build message list with grouping
                      final groupedMessages = <String, List<Map<String, dynamic>>>{};
                      for (final doc in messages) {
                        final data = doc.data() as Map<String, dynamic>;
                        final createdAt = data['createdAt'] as Timestamp?;
                        if (createdAt != null) {
                          final group = _getMessageGroup(createdAt.toDate());
                          if (!groupedMessages.containsKey(group)) {
                            groupedMessages[group] = [];
                          }
                          groupedMessages[group]!.add({...data, 'id': doc.id});
                        }
                      }

                      // Create widget list with group headers
                      final widgets = <Widget>[];
                      final groupKeys = groupedMessages.keys.toList();
                      // Order: Today, Yesterday, This Week, This Month, Older
                      final order = ['Today', 'Yesterday', 'This Week', 'This Month', 'Older'];
                      groupKeys.sort((a, b) {
                        final aIndex = order.indexOf(a);
                        final bIndex = order.indexOf(b);
                        return (aIndex == -1 ? 999 : aIndex).compareTo(bIndex == -1 ? 999 : bIndex);
                      });

                      for (final key in groupKeys) {
                        // Add group header
                        widgets.add(
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(20),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  key,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: fontSize * 0.85,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );

                        // Add messages in this group
                        final groupMessages = groupedMessages[key]!;
                        for (final data in groupMessages) {
                          widgets.add(_buildMessageWidget(data, fontSize, maxWidth));
                        }
                      }

                      // Add loading indicator at bottom when loading more
                      if (_isLoadingMore) {
                        widgets.add(
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: widgets.length,
                        itemBuilder: (context, index) => widgets[index],
                      );
                    },
                  ),
                ),
                // Input bar with reply indicator
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.primary.withAlpha(20))),
                  ),
                  child: Column(
                    children: [
                      if (_isReplying)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Replying to',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: fontSize * 0.77,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      _replyToText ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: fontSize,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: _cancelReply,
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          if (_isUploading)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                              onPressed: _pickAndSendPhoto,
                            ),
                            GestureDetector(
                              onLongPress: _startRecording,
                              onLongPressUp: _stopRecording,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isRecording ? AppColors.error.withAlpha(26) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Icon(
                                  _isRecording ? Icons.mic : Icons.mic_none,
                                  color: _isRecording ? AppColors.error : AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: _isReplying ? 'Type your reply...' : 'Type a message...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onSubmitted: (text) => _sendMessage(text: text),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _sendMessage(text: _messageController.text),
                            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Scroll to bottom button
            if (_showScrollToBottom)
              Positioned(
                bottom: 100,
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottom,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageWidget(Map<String, dynamic> message, double fontSize, double maxWidth) {
    final isMine = message['senderId'] == _currentUser?.uid;
    final type = message['type'] ?? 'text';
    final text = message['text'] ?? '';
    final photoUrl = message['photoUrl'];
    final voiceUrl = message['voiceUrl'];
    final voiceDuration = message['voiceDuration'] as int?;
    final readAt = message['readAt'];
    final replyTo = message['replyTo'] as String?;
    final reactions = List<String>.from(message['reactions'] ?? []);
    final isEdited = message['isEdited'] ?? false;
    final isDeleted = message['isDeleted'] ?? false;

    // If message is deleted, show a placeholder
    if (isDeleted) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '[deleted]',
            style: TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
              fontSize: fontSize,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Reply indicator
            if (replyTo != null) ...[
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .doc(replyTo)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final replyData = snapshot.data!.data() as Map<String, dynamic>?;
                  if (replyData == null) return const SizedBox.shrink();
                  final replyText = replyData['text'] ?? '[deleted]';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: fontSize * 0.77,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          replyText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: fontSize * 0.92,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            // Message content
            GestureDetector(
              onLongPress: () {
                _showMessageMenu(
                  messageId: message['id'],
                  messageText: text,
                  messageType: type,
                  reactions: reactions,
                );
              },
              child: _buildMessageContent(
                type: type,
                text: text,
                photoUrl: photoUrl,
                voiceUrl: voiceUrl,
                voiceDuration: voiceDuration,
                isMine: isMine,
                isEdited: isEdited,
                reactions: reactions,
                fontSize: fontSize,
              ),
            ),
            // Reactions row
            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: reactions.map((emoji) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.textSecondary.withAlpha(40)),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                ),
              ),
            // Timestamp + read status
            if (isMine) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatMessageTime(message['createdAt'] as Timestamp?),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize * 0.77,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (isEdited)
                    Text(
                      'edited',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: fontSize * 0.69,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    readAt != null ? Icons.done_all : Icons.done,
                    size: 14,
                    color: readAt != null ? AppColors.success : AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent({
    required String type,
    required String text,
    String? photoUrl,
    String? voiceUrl,
    int? voiceDuration,
    required bool isMine,
    required bool isEdited,
    required List<String> reactions,
    required double fontSize,
  }) {
    if (type == 'photo' && photoUrl != null) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black),
              body: Center(child: Image.network(ImageOptimizer.original(photoUrl))),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            ImageOptimizer.medium(photoUrl, width: 300, height: 300),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (type == 'voice' && voiceUrl != null) {
      return _VoiceBubble(
        voiceUrl: voiceUrl,
        voiceDuration: voiceDuration ?? 0,
        isMine: isMine,
        isPlaying: _isPlaying && _playingVoiceUrl == voiceUrl,
        playbackSpeed: _playbackSpeed,
        onPlay: () => _playVoice(voiceUrl),
        onSpeedCycle: _cycleSpeed,
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: isMine ? null : Border.all(color: AppColors.primary.withAlpha(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                color: isMine ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }
  }

  // ========== PAGINATION: LOAD MORE MESSAGES ==========

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _lastDocument == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
          _isLoadingMore = false;
        });
        return;
      }

      // Update last document for next pagination
      _lastDocument = snapshot.docs.last;

      setState(() => _isLoadingMore = false);

    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }
}

// ========== VOICE BUBBLE WIDGET ==========

class _VoiceBubble extends StatefulWidget {
  final String voiceUrl;
  final int voiceDuration;
  final bool isMine;
  final bool isPlaying;
  final double playbackSpeed;
  final VoidCallback onPlay;
  final VoidCallback onSpeedCycle;

  const _VoiceBubble({required this.voiceUrl, required this.voiceDuration, required this.isMine, required this.isPlaying, required this.playbackSpeed, required this.onPlay, required this.onSpeedCycle});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _audioPlayer = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.voiceDuration);
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _seekTo(double value) {
    final target = Duration(milliseconds: (value * _duration.inMilliseconds).round());
    _audioPlayer.seek(target);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMine ? AppColors.primary : AppColors.surface;
    final textColor = widget.isMine ? Colors.white : AppColors.textPrimary;
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;

    final screenWidth = MediaQuery.of(context).size.width;
    final bubbleWidth = screenWidth < 380 ? 120.0 : (screenWidth < 600 ? 160.0 : 200.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: widget.isMine ? null : Border.all(color: AppColors.primary.withAlpha(20)),
      ),
      child: SizedBox(
        width: bubbleWidth,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: widget.onPlay,
              child: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow, color: textColor, size: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTapDown: (details) {
                  final box = context.findRenderObject() as RenderBox;
                  final localX = details.localPosition.dx;
                  final width = box.size.width - 56;
                  _seekTo((localX - 44) / width);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: textColor.withAlpha(51),
                    color: textColor,
                    minHeight: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_position),
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: textColor),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: widget.onSpeedCycle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: textColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.playbackSpeed}x',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}