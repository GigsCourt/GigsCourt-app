const functions = require("firebase-functions");
const admin = require("./admin");

exports.checkSubscriptionExpiry = functions.scheduler
  .onSchedule('every 1 hours', async (event) => {
    const db = admin.firestore();
    const now = new Date().toISOString();

    const expiredUsers = await db.collection('users')
      .where('subscriptionStatus', '==', 'premium')
      .where('subscriptionExpiry', '<=', now)
      .get();

    const batch = db.batch();
    expiredUsers.forEach((doc) => {
      batch.update(doc.ref, {
        subscriptionStatus: 'locked',
        subscriptionExpiry: null,
      });
    });

    if (expiredUsers.size > 0) {
      await batch.commit();
      console.log(`Expired ${expiredUsers.size} subscriptions`);
    }
  });