const functions = require("firebase-functions");
const admin = require("firebase-admin");
const ImageKit = require("imagekit");

admin.initializeApp();

const imagekit = new ImageKit({
  publicKey: "public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=",
  privateKey: "YOUR_PRIVATE_KEY",
  urlEndpoint: "https://ik.imagekit.io/GigsKourt"
});

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
    await admin.auth().verifyIdToken(idToken);
    const params = imagekit.getAuthenticationParameters();
    res.json(params);
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});