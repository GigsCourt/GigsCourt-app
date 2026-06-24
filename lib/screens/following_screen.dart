import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/image_optimizer.dart';

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'Following',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('following')
            .orderBy('followedAt', descending: true)
            .snapshots(),
        builder: (context, followingSnapshot) {
          if (!followingSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final followingDocs = followingSnapshot.data!.docs;

          if (followingDocs.isEmpty) {
            return const Center(
              child: Text(
                'You\'re not following anyone yet.',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
              ),
            );
          }

          final followingUserIds = followingDocs.map((doc) => doc.id).toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where(FieldPath.documentId, whereIn: followingUserIds)
                .snapshots(),
            builder: (context, usersSnapshot) {
              if (!usersSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final userDocs = usersSnapshot.data!.docs;
              final userMap = <String, Map<String, dynamic>>{};
              for (final doc in userDocs) {
                userMap[doc.id] = doc.data() as Map<String, dynamic>;
              }

              // Maintain order from the following sub-collection
              final orderedUsers = followingUserIds
                  .where((id) => userMap.containsKey(id))
                  .map((id) => {'id': id, ...userMap[id]!})
                  .toList();

              if (orderedUsers.isEmpty) {
                return const Center(
                  child: Text(
                    'No following users found.',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orderedUsers.length,
                itemBuilder: (context, index) {
                  final pData = orderedUsers[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: pData['photoUrl'] != null
                            ? Image.network(
                                ImageOptimizer.thumbnail(pData['photoUrl']),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: AppColors.primary.withAlpha(26),
                                    child: Icon(Icons.person, color: AppColors.primary),
                                  );
                                },
                              )
                            : Container(
                                color: AppColors.primary.withAlpha(26),
                                child: Icon(Icons.person, color: AppColors.primary),
                              ),
                      ),
                    ),
                    title: Text(
                      pData['displayName'] ?? 'Unknown',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      pData['bio'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/provider-profile',
                        arguments: pData['id'],
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
}