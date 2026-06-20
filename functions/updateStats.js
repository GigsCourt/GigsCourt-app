const functions = require("firebase-functions");

exports.updateStats = functions.firestore
  .onDocumentWritten('users/{userId}', async (event) => {
    const admin = require("./admin");
    const db = admin.firestore();
    const statsRef = db.collection('stats').doc('counts');

    const usersSnap = await db.collection('users').get();
    let subscribers = 0;
    usersSnap.forEach((doc) => {
      if (doc.data().subscriptionStatus === 'premium') subscribers++;
    });

    await statsRef.set({
      users: usersSnap.size,
      subscribers: subscribers,
    }, { merge: true });
  });