const functions = require("firebase-functions");
const crypto = require("crypto");

const IMAGEKIT_PRIVATE_KEY = process.env.IMAGEKIT_PRIVATE_KEY;

exports.getImageKitToken = functions.https.onRequest(async (req, res) => {
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
    
    const token = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 3600;
    
    const signature = crypto
      .createHmac("sha1", IMAGEKIT_PRIVATE_KEY)
      .update(token + expire)
      .digest("hex");
    
    res.json({ token, expire, signature });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});