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

    const db = admin.firestore();
    const userRef = db.collection('users').doc(providerId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const data = userDoc.data();
    const currentStatus = data.subscriptionStatus || 'free';

    if (currentStatus === 'premium' || currentStatus === 'locked') {
      return res.json({ success: true, status: currentStatus });
    }

    let leadCount = data.leadCount || 0;
    let reviewCount = data.reviewCount || 0;

    if (type === 'lead') leadCount += 1;
    if (type === 'review') reviewCount += 1;

    const updates = { leadCount, reviewCount };

    if (leadCount >= 10 || reviewCount >= 5) {
      updates.subscriptionStatus = 'locked';
    }

    await userRef.update(updates);

    res.json({
      success: true,
      status: updates.subscriptionStatus || currentStatus,
      leadCount,
      reviewCount,
    });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});