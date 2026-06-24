const functions = require("firebase-functions");
const admin = require("./admin");

const db = admin.firestore();

exports.checkSubscriptionExpiry = functions.scheduler
  .onSchedule('every 1 hours', async (event) => {
    const now = new Date().toISOString();

    try {
      const expiredUsers = await db.collection('users')
        .where('subscriptionStatus', '==', 'premium')
        .where('subscriptionExpiry', '<=', now)
        .get();

      if (expiredUsers.empty) {
        console.log('No expired subscriptions found');
        return null;
      }

      const batch = db.batch();
      const expiredUserIds = [];

      expiredUsers.forEach((doc) => {
        const userId = doc.id;
        expiredUserIds.push(userId);
        
        batch.update(doc.ref, {
          subscriptionStatus: 'locked',
          subscriptionExpiry: null,
        });
      });

      await batch.commit();
      console.log(`Expired ${expiredUsers.size} subscriptions`);

      // ✅ SEND NOTIFICATIONS TO SUB-COLLECTIONS
      for (const userId of expiredUserIds) {
        try {
          await db.collection('users').doc(userId).collection('notifications').add({
            userId: userId,
            title: 'Your Subscription Has Expired',
            body: 'Your premium subscription has expired. Subscribe again to continue receiving unlimited leads and reviews.',
            type: 'subscription',
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (notifyError) {
          console.error(`Failed to send expiry notification to ${userId}:`, notifyError);
        }
      }

      return null;
    } catch (error) {
      console.error('Subscription expiry check failed:', error);
      return null;
    }
  });