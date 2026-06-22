import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class ReviewsScreen extends StatefulWidget {
  final String providerId;

  const ReviewsScreen({super.key, required this.providerId});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reviews = [];
  Map<String, List<Map<String, dynamic>>> _clientHistories = {};
  final Set<String> _expandedClients = {};

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('providerId', isEqualTo: widget.providerId)
          .orderBy('createdAt', descending: true)
          .get();

      final Map<String, List<Map<String, dynamic>>> histories = {};
      final Map<String, Map<String, dynamic>> latestReviews = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final clientId = data['clientId'] as String;
        final review = {...data, 'id': doc.id};

        // Build history
        if (!histories.containsKey(clientId)) {
          histories[clientId] = [];
        }
        histories[clientId]!.add(review);

        // Latest per client
        if (!latestReviews.containsKey(clientId)) {
          latestReviews[clientId] = review;
        }
      }

      final sortedReviews = latestReviews.values.toList();
      sortedReviews.sort((a, b) {
        final aTime = (a['createdAt'] as Timestamp).toDate();
        final bTime = (b['createdAt'] as Timestamp).toDate();
        return bTime.compareTo(aTime);
      });

      setState(() {
        _reviews = sortedReviews;
        _clientHistories = histories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Reviews',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reviews.isEmpty
              ? const Center(
                  child: Text('No reviews yet.',
                      style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reviews.length,
                  itemBuilder: (context, index) {
                    final review = _reviews[index];
                    final clientId = review['clientId'] as String;
                    final history = _clientHistories[clientId] ?? [];
                    final isExpanded = _expandedClients.contains(clientId);
                    final hasHistory = history.length > 1;
                    final rating = (review['rating'] as num?)?.toDouble() ?? 0.0;
                    final comment = review['comment'] as String? ?? '';
                    final createdAt = review['createdAt'] as Timestamp?;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withAlpha(20)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildStars(rating),
                              const SizedBox(width: 8),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(createdAt),
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          if (comment.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              comment,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                  height: 1.4),
                            ),
                          ],
                          if (hasHistory) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedClients.remove(clientId);
                                  } else {
                                    _expandedClients.add(clientId);
                                  }
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${history.length - 1} previous review${history.length > 2 ? 's' : ''}',
                                    style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                            if (isExpanded)
                              ...history.skip(1).map((oldReview) {
                                final oldRating = (oldReview['rating'] as num?)?.toDouble() ?? 0.0;
                                final oldComment = oldReview['comment'] as String? ?? '';
                                final oldDate = oldReview['createdAt'] as Timestamp?;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8, left: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _buildStars(oldRating),
                                          const SizedBox(width: 4),
                                          Text(_formatDate(oldDate),
                                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                      if (oldComment.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(oldComment,
                                              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary)),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating.round() ? Icons.star : Icons.star_border,
          color: AppColors.accent,
          size: 18,
        );
      }),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}