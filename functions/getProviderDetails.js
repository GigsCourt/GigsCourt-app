const functions = require("firebase-functions");

exports.getProviderDetails = functions.https.onRequest(async (req, res) => {
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

    const { userIds } = req.body;
    if (!userIds || !Array.isArray(userIds)) {
      res.status(400).json({ error: 'userIds array required' });
      return;
    }

    const db = admin.firestore();
    const results = {};

    const providerPromises = userIds.map(async (uid) => {
      const providerDoc = await db.collection('providers').doc(uid).get();
      const userDoc = await db.collection('users').doc(uid).get();
      return {
        userId: uid,
        provider: providerDoc.exists ? providerDoc.data() : null,
        user: userDoc.exists ? userDoc.data() : null,
      };
    });

    const data = await Promise.all(providerPromises);

    data.forEach((item) => {
      results[item.userId] = {
        provider: item.provider,
        user: item.user,
      };
    });

    res.json({ results });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});