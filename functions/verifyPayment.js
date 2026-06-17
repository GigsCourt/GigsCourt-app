const functions = require("firebase-functions");
const https = require("https");

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_SECRET_KEY;

exports.verifyPayment = functions.https.onRequest(async (req, res) => {
  const { reference } = req.body;
  if (!reference) {
    res.status(400).json({ error: 'reference required' });
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

  https.get(options, (paystackRes) => {
    let data = '';
    paystackRes.on('data', (chunk) => { data += chunk; });
    paystackRes.on('end', async () => {
      const response = JSON.parse(data);
      if (response.status && response.data.status === 'success') {
        const userId = response.data.metadata.userId;
        const admin = require("./admin");
        await admin.firestore().collection('providers').doc(userId).update({
          subscriptionStatus: 'premium',
          subscriptionExpiry: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        });
        res.json({ success: true });
      } else {
        res.status(400).json({ error: 'Payment verification failed' });
      }
    });
  }).on('error', (e) => {
    res.status(500).json({ error: e.message });
  });
});