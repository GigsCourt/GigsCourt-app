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
        title: const Text('Following',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final following = List<String>.from(data['following'] ?? []);

          if (following.isEmpty) {
            return const Center(
              child: Text('You\'re not following anyone yet.',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: following.length,
            itemBuilder: (context, index) {
              final providerId = following[index];
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(providerId).get(),
                builder: (context, providerSnap) {
                  if (!providerSnap.hasData) return const SizedBox();
                  final pData = providerSnap.data!.data() as Map<String, dynamic>?;
                  if (pData == null) return const SizedBox();
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 48, height: 48,
                        child: pData['photoUrl'] != null
                            ? Image.network(ImageOptimizer.thumbnail(pData['photoUrl']), fit: BoxFit.cover)
                            : Container(color: AppColors.primary.withAlpha(26), child: Icon(Icons.person, color: AppColors.primary)),
                      ),
                    ),
                    title: Text(pData['displayName'] ?? 'Unknown',
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                    subtitle: Text(pData['bio'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pushNamed('/provider-profile', arguments: providerId);
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