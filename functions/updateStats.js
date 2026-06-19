const functions = require("firebase-functions");

exports.updateStats = functions.firestore
  .onDocumentWritten('providers/{userId}', async (event) => {
    const admin = require("./admin");
    const db = admin.firestore();
    const statsRef = db.collection('stats').doc('counts');

    const providersSnap = await db.collection('providers').get();
    const usersSnap = await db.collection('users').get();
    let subscribers = 0;
    providersSnap.forEach((doc) => {
      if (doc.data().subscriptionStatus === 'premium') subscribers++;
    });

    await statsRef.set({
      users: usersSnap.size,
      providers: providersSnap.size,
      subscribers: subscribers,
    }, { merge: true });
  });