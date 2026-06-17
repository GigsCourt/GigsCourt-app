const functions = require("firebase-functions");

exports.getSubscriptionPrice = functions.https.onRequest(async (req, res) => {
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

    const { countryCode } = req.body;
    if (!countryCode) {
      res.status(400).json({ error: 'countryCode required' });
      return;
    }

    const db = admin.firestore();

    // Check country-specific override
    const countryDoc = await db.collection('config').doc(`pricing_${countryCode}`).get();
    if (countryDoc.exists) {
      return res.json(countryDoc.data());
    }

    // Check region overrides for Europe
    const euCountries = ['DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'IE', 'PT', 'GR', 'FI', 'SK', 'SI', 'LT', 'LV', 'EE', 'CY', 'MT', 'LU', 'HR'];
    if (euCountries.includes(countryCode)) {
      const euDoc = await db.collection('config').doc('pricing_EU').get();
      if (euDoc.exists) return res.json(euDoc.data());
    }

    // Check Africa override
    const africaCountries = ['GH', 'KE', 'ZA', 'EG', 'ET', 'TZ', 'UG', 'RW', 'SN', 'CI', 'CM', 'MA', 'TN', 'BW', 'MU', 'NA', 'ZM', 'ZW', 'MW', 'SD'];
    if (africaCountries.includes(countryCode)) {
      const africaDoc = await db.collection('config').doc('pricing_AFRICA').get();
      if (africaDoc.exists) return res.json(africaDoc.data());
    }

    // Check Asia override
    const asiaCountries = ['IN', 'PK', 'BD', 'ID', 'PH', 'VN', 'TH', 'MY', 'SG', 'JP', 'KR', 'CN', 'HK', 'TW', 'LK', 'NP', 'MM', 'KH'];
    if (asiaCountries.includes(countryCode)) {
      const asiaDoc = await db.collection('config').doc('pricing_ASIA').get();
      if (asiaDoc.exists) return res.json(asiaDoc.data());
    }

    // GB override
    if (countryCode === 'GB') {
      const gbDoc = await db.collection('config').doc('pricing_GB').get();
      if (gbDoc.exists) return res.json(gbDoc.data());
    }

    // US override
    if (countryCode === 'US') {
      const usDoc = await db.collection('config').doc('pricing_US').get();
      if (usDoc.exists) return res.json(usDoc.data());
    }

    // CA override
    if (countryCode === 'CA') {
      const caDoc = await db.collection('config').doc('pricing_CA').get();
      if (caDoc.exists) return res.json(caDoc.data());
    }

    // Default: Remote Config values (hardcoded as fallback)
    res.json({
      amount: 10,
      currency: 'USD',
    });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});