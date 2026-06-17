const functions = require("firebase-functions");
const https = require("https");

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_SECRET_KEY;

exports.initializePayment = functions.https.onRequest(async (req, res) => {
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
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const userId = decodedToken.uid;

    const { email, amount, currency } = req.body;
    if (!email || !amount) {
      res.status(400).json({ error: 'email and amount required' });
      return;
    }

    const params = JSON.stringify({
      email,
      amount: Math.round(amount * 100), // Paystack expects kobo/cents
      currency: currency || 'NGN',
      metadata: { userId },
    });

    const options = {
      hostname: 'api.paystack.co',
      port: 443,
      path: '/transaction/initialize',
      method: 'POST',
      headers: {
        Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
    };

    const paystackReq = https.request(options, (paystackRes) => {
      let data = '';
      paystackRes.on('data', (chunk) => { data += chunk; });
      paystackRes.on('end', () => {
        const response = JSON.parse(data);
        if (response.status && response.data) {
          res.json({
            authorizationUrl: response.data.authorization_url,
            reference: response.data.reference,
          });
        } else {
          res.status(500).json({ error: 'Payment initialization failed' });
        }
      });
    });

    paystackReq.on('error', (e) => {
      res.status(500).json({ error: e.message });
    });

    paystackReq.write(params);
    paystackReq.end();
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});