const functions = require("firebase-functions");

exports.createNotification = functions.https.onRequest(async (req, res) => {
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

    const { userId, title, body, type, referenceId } = req.body;
    if (!userId || !title || !body) {
      res.status(400).json({ error: 'userId, title, and body are required' });
      return;
    }

    const db = admin.firestore();
    await db.collection('notifications').add({
      userId,
      title,
      body,
      type: type || 'general',
      referenceId: referenceId || null,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send push notification
    try {
      const userDoc = await db.collection('users').doc(userId).get();
      const userData = userDoc.data();
      
      if (userData && userData.fcmToken && userData.pushNotifications !== false) {
        await admin.messaging().send({
          token: userData.fcmToken,
          notification: {
            title: title,
            body: body,
          },
          data: {
            type: type || 'general',
            referenceId: referenceId || '',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        });
      }
    } catch (pushError) {
      console.log('Push notification failed:', pushError);
    }

    res.json({ success: true });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});