const functions = require('firebase-functions');
const crypto = require('crypto');

const PRIVATE_KEY = 'YOUR_IMAGEKIT_PRIVATE_KEY';

exports.getImageKitToken = functions.https.onCall((data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const token = crypto.randomUUID();
  const expire = Math.floor(Date.now() / 1000) + 3600; // 1 hour

  const signature = crypto
    .createHmac('sha1', PRIVATE_KEY)
    .update(token + expire)
    .digest('hex');

  return {
    token: token,
    expire: expire,
    signature: signature,
  };
});