const functions = require("firebase-functions");

exports.trackEngagement = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');

  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    res.status(204).send('');
    return;
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const idToken = authHeader.split('Bearer ')[1];

  try {
    const admin = require("./admin");
    await admin.auth().verifyIdToken(idToken);

    const { providerId, type } = req.body;
    if (!providerId || !type) {
      res.status(400).json({ error: 'providerId and type required' });
      return;
    }

    if (type !== 'lead' && type !== 'review') {
      res.status(400).json({ error: 'type must be "lead" or "review"' });
      return;
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(providerId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const data = userDoc.data();
    const currentStatus = data.subscriptionStatus || 'free';

    // Premium and locked users don't need tracking
    if (currentStatus === 'premium') {
      return res.json({ success: true, status: 'premium' });
    }

    if (currentStatus === 'locked') {
      return res.json({ success: true, status: 'locked' });
    }

    // Free user → track
    let leadCount = data.leadCount || 0;
    let reviewCount = data.reviewCount || 0;

    if (type === 'lead') leadCount += 1;
    if (type === 'review') reviewCount += 1;

    const updates = { leadCount, reviewCount };

    if (leadCount >= 10 || reviewCount >= 5) {
      updates.subscriptionStatus = 'locked';

      // ✅ SEND NOTIFICATION TO SUB-COLLECTION
      try {
        await db.collection('users').doc(providerId).collection('notifications').add({
          userId: providerId,
          title: 'You\'ve reached your free limit!',
          body: 'You\'ve reached the maximum number of free leads or reviews. Subscribe to continue receiving clients.',
          type: 'subscription',
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (notifyError) {
        console.error('Failed to send limit notification:', notifyError);
      }
    }

    // ✅ FOR REVIEWS: Also save to reviews sub-collection
    if (type === 'review') {
      try {
        // Get the review data from the request (passed from the client)
        const { rating, comment } = req.body;
        if (rating) {
          await db.collection('users').doc(providerId).collection('reviews').add({
            providerId: providerId,
            clientId: req.body.clientId || null,
            rating: rating,
            comment: comment || '',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } catch (reviewError) {
        console.error('Failed to save review to sub-collection:', reviewError);
      }
    }

    await userRef.update(updates);

    res.json({
      success: true,
      status: updates.subscriptionStatus || currentStatus,
      leadCount,
      reviewCount,
    });
  } catch (e) {
    console.error('Track engagement failed:', e);
    res.status(401).json({ error: 'Invalid token' });
  }
});