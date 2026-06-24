const functions = require("firebase-functions");
const https = require("https");

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_SECRET_KEY;

exports.verifyPayment = functions.https.onRequest(async (req, res) => {
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
  let userId;
  let email;

  try {
    const admin = require("./admin");
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    userId = decodedToken.uid;
    email = decodedToken.email;
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
    return;
  }

  const { reference } = req.body;
  if (!reference) {
    res.status(400).json({ error: 'reference required' });
    return;
  }

  if (!PAYSTACK_SECRET_KEY) {
    console.error('PAYSTACK_SECRET_KEY is not set');
    res.status(500).json({ error: 'Payment verification failed' });
    return;
  }

  const options = {
    hostname: 'api.paystack.co',
    port: 443,
    path: `/transaction/verify/${reference}`,
    method: 'GET',
    headers: {
      Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
    },
  };

  const paystackReq = https.get(options, (paystackRes) => {
    let data = '';
    paystackRes.on('data', (chunk) => { data += chunk; });
    paystackRes.on('end', async () => {
      try {
        const response = JSON.parse(data);

        if (response.status && response.data.status === 'success') {
          const metadataUserId = response.data.metadata?.userId;

          if (!metadataUserId) {
            console.error('No userId in metadata');
            res.status(400).json({ error: 'Payment verification failed' });
            return;
          }

          if (metadataUserId !== userId) {
            console.error(`User mismatch: ${metadataUserId} !== ${userId}`);
            res.status(403).json({ error: 'Forbidden' });
            return;
          }

          const admin = require("./admin");
          const db = admin.firestore();

          // ✅ UPDATE USER
          await db.collection('users').doc(userId).update({
            subscriptionStatus: 'premium',
            subscriptionExpiry: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
            leadCount: 0,
            reviewCount: 0,
          });

          // ✅ SEND NOTIFICATION TO SUB-COLLECTION
          try {
            await db.collection('users').doc(userId).collection('notifications').add({
              userId: userId,
              title: 'Subscription Activated!',
              body: 'Your premium subscription is now active. You can now receive unlimited leads and reviews.',
              type: 'subscription',
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (notifyError) {
            console.error('Failed to send subscription notification:', notifyError);
          }

          console.log(`User ${userId} subscribed successfully`);
          res.json({ success: true });

        } else {
          console.error('Payment verification failed:', response);
          res.status(400).json({ error: 'Payment verification failed' });
        }
      } catch (e) {
        console.error('Error parsing Paystack response:', e);
        res.status(500).json({ error: 'Payment verification failed' });
      }
    });
  });

  paystackReq.on('error', (e) => {
    console.error('Paystack request error:', e);
    res.status(500).json({ error: 'Payment verification failed' });
  });

  paystackReq.end();
});

// ========== PAYSTACK WEBHOOK ==========

exports.paystackWebhook = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');

  const signature = req.headers['x-paystack-signature'];
  if (!signature) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const crypto = require('crypto');
  const expectedSignature = crypto
    .createHmac('sha512', PAYSTACK_SECRET_KEY)
    .update(JSON.stringify(req.body))
    .digest('hex');

  if (signature !== expectedSignature) {
    res.status(401).json({ error: 'Invalid signature' });
    return;
  }

  const event = req.body;

  try {
    const admin = require("./admin");
    const db = admin.firestore();

    if (event.event === 'charge.success') {
      const data = event.data;
      const userId = data.metadata?.userId;
      const reference = data.reference;

      if (!userId) {
        console.error('No userId in webhook metadata');
        res.status(400).json({ error: 'Invalid webhook data' });
        return;
      }

      // Check if already processed (idempotency)
      const existingTx = await db.collection('transactions').doc(reference).get();
      if (existingTx.exists) {
        console.log(`Transaction ${reference} already processed`);
        res.json({ success: true });
        return;
      }

      // Mark transaction as processed
      await db.collection('transactions').doc(reference).set({
        userId: userId,
        reference: reference,
        amount: data.amount / 100,
        currency: data.currency,
        status: 'success',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // ✅ UPDATE USER
      await db.collection('users').doc(userId).update({
        subscriptionStatus: 'premium',
        subscriptionExpiry: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        leadCount: 0,
        reviewCount: 0,
      });

      // ✅ SEND NOTIFICATION TO SUB-COLLECTION
      await db.collection('users').doc(userId).collection('notifications').add({
        userId: userId,
        title: 'Subscription Activated!',
        body: 'Your premium subscription is now active.',
        type: 'subscription',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Webhook: User ${userId} subscribed successfully`);
      res.json({ success: true });

    } else {
      console.log(`Webhook: Unhandled event ${event.event}`);
      res.json({ success: true });
    }

  } catch (e) {
    console.error('Webhook error:', e);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});