// ========== SERVICE ACCOUNT CREDENTIALS ==========
const admin = require('firebase-admin');
const path = require('path');

// Load service account key
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin with credentials
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

// ========== CONFIGURATION ==========
const BATCH_SIZE = 500; // Firestore batch write limit
const DRY_RUN = process.argv.includes('--dry-run'); // Run with --dry-run to preview

// ========== UTILITY FUNCTIONS ==========

function log(message, data = null) {
  if (data) {
    console.log(`[MIGRATION] ${message}`, data);
  } else {
    console.log(`[MIGRATION] ${message}`);
  }
}

function logError(message, error) {
  console.error(`[MIGRATION ERROR] ${message}`, error);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function processBatch(batchOperations) {
  if (DRY_RUN) {
    log(`[DRY RUN] Would write ${batchOperations.length} operations`);
    return;
  }

  const batch = db.batch();
  for (const op of batchOperations) {
    batch.set(op.ref, op.data, { merge: true });
  }
  await batch.commit();
}

// ========== MIGRATION 1: REVIEWS ==========

async function migrateReviews() {
  log('Starting reviews migration...');

  const snapshot = await db.collection('reviews').get();
  const total = snapshot.docs.length;
  log(`Found ${total} reviews to migrate`);

  let processed = 0;
  let batchOps = [];
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const providerId = data.providerId;

    if (!providerId) {
      logError(`Review ${doc.id} has no providerId, skipping`);
      continue;
    }

    const newRef = db
      .collection('users')
      .doc(providerId)
      .collection('reviews')
      .doc(doc.id);

    batchOps.push({
      ref: newRef,
      data: {
        ...data,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        _migratedFrom: 'reviews',
      },
    });

    processed++;

    // Flush batch when it reaches the limit
    if (batchOps.length >= BATCH_SIZE) {
      batchCount++;
      log(`Processing review batch ${batchCount} (${processed}/${total})`);
      await processBatch(batchOps);
      batchOps = [];

      // Small delay to avoid rate limiting
      await sleep(100);
    }
  }

  // Flush remaining
  if (batchOps.length > 0) {
    batchCount++;
    log(`Processing final review batch ${batchCount} (${processed}/${total})`);
    await processBatch(batchOps);
  }

  log(`Reviews migration complete. Processed ${processed} reviews.`);
}

// ========== MIGRATION 2: NOTIFICATIONS ==========

async function migrateNotifications() {
  log('Starting notifications migration...');

  const snapshot = await db.collection('notifications').get();
  const total = snapshot.docs.length;
  log(`Found ${total} notifications to migrate`);

  let processed = 0;
  let batchOps = [];
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const userId = data.userId;

    if (!userId) {
      logError(`Notification ${doc.id} has no userId, skipping`);
      continue;
    }

    const newRef = db
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .doc(doc.id);

    batchOps.push({
      ref: newRef,
      data: {
        ...data,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        _migratedFrom: 'notifications',
      },
    });

    processed++;

    if (batchOps.length >= BATCH_SIZE) {
      batchCount++;
      log(`Processing notification batch ${batchCount} (${processed}/${total})`);
      await processBatch(batchOps);
      batchOps = [];
      await sleep(100);
    }
  }

  if (batchOps.length > 0) {
    batchCount++;
    log(`Processing final notification batch ${batchCount} (${processed}/${total})`);
    await processBatch(batchOps);
  }

  log(`Notifications migration complete. Processed ${processed} notifications.`);
}

// ========== MIGRATION 3: TICKETS ==========

async function migrateTickets() {
  log('Starting tickets migration...');

  const snapshot = await db.collection('tickets').get();
  const total = snapshot.docs.length;
  log(`Found ${total} tickets to migrate`);

  let processed = 0;
  let batchOps = [];
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    // Use submittedBy as the primary userId, fallback to targetUserId
    const userId = data.submittedBy || data.targetUserId;

    if (!userId) {
      logError(`Ticket ${doc.id} has no userId, skipping`);
      continue;
    }

    const newRef = db
      .collection('users')
      .doc(userId)
      .collection('tickets')
      .doc(doc.id);

    batchOps.push({
      ref: newRef,
      data: {
        ...data,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        _migratedFrom: 'tickets',
      },
    });

    processed++;

    if (batchOps.length >= BATCH_SIZE) {
      batchCount++;
      log(`Processing ticket batch ${batchCount} (${processed}/${total})`);
      await processBatch(batchOps);
      batchOps = [];
      await sleep(100);
    }
  }

  if (batchOps.length > 0) {
    batchCount++;
    log(`Processing final ticket batch ${batchCount} (${processed}/${total})`);
    await processBatch(batchOps);
  }

  log(`Tickets migration complete. Processed ${processed} tickets.`);
}

// ========== MIGRATION 4: FOLLOWING/FOLLOWERS ==========

async function migrateFollowing() {
  log('Starting following/followers migration...');

  const snapshot = await db.collection('users').get();
  const total = snapshot.docs.length;
  log(`Found ${total} users to process for following`);

  let processed = 0;
  let batchOps = [];
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const userId = doc.id;
    const following = data.following || [];

    if (following.length === 0) {
      processed++;
      continue;
    }

    log(`User ${userId} follows ${following.length} users`);

    // Create following sub-collection for this user
    for (const followedUserId of following) {
      const followingRef = db
        .collection('users')
        .doc(userId)
        .collection('following')
        .doc(followedUserId);

      batchOps.push({
        ref: followingRef,
        data: {
          followedAt: data['followedAt_' + followedUserId] || admin.firestore.FieldValue.serverTimestamp(),
          _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });

      // Also create reverse lookup: followers sub-collection for the followed user
      const followerRef = db
        .collection('users')
        .doc(followedUserId)
        .collection('followers')
        .doc(userId);

      batchOps.push({
        ref: followerRef,
        data: {
          followedAt: data['followedAt_' + followedUserId] || admin.firestore.FieldValue.serverTimestamp(),
          _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }

    processed++;

    if (batchOps.length >= BATCH_SIZE) {
      batchCount++;
      log(`Processing following batch ${batchCount} (${processed}/${total})`);
      await processBatch(batchOps);
      batchOps = [];
      await sleep(100);
    }
  }

  if (batchOps.length > 0) {
    batchCount++;
    log(`Processing final following batch ${batchCount} (${processed}/${total})`);
    await processBatch(batchOps);
  }

  log(`Following/followers migration complete. Processed ${processed} users.`);
}

// ========== MIGRATION 5: VERIFICATION ==========

async function verifyMigration() {
  log('Starting verification...');

  const results = {
    reviews: { old: 0, new: 0 },
    notifications: { old: 0, new: 0 },
    tickets: { old: 0, new: 0 },
  };

  // Count old collections
  const reviewsOld = await db.collection('reviews').get();
  results.reviews.old = reviewsOld.size;

  const notificationsOld = await db.collection('notifications').get();
  results.notifications.old = notificationsOld.size;

  const ticketsOld = await db.collection('tickets').get();
  results.tickets.old = ticketsOld.size;

  // Count new sub-collections (this is approximate since we need to count across all users)
  // We'll count by checking if any documents exist in the new structure
  const usersSnapshot = await db.collection('users').limit(100).get();
  let reviewsNewCount = 0;
  let notificationsNewCount = 0;
  let ticketsNewCount = 0;

  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;

    const reviewsNew = await db.collection('users').doc(userId).collection('reviews').limit(10).get();
    reviewsNewCount += reviewsNew.size;

    const notificationsNew = await db.collection('users').doc(userId).collection('notifications').limit(10).get();
    notificationsNewCount += notificationsNew.size;

    const ticketsNew = await db.collection('users').doc(userId).collection('tickets').limit(10).get();
    ticketsNewCount += ticketsNew.size;
  }

  results.reviews.new = reviewsNewCount;
  results.notifications.new = notificationsNewCount;
  results.tickets.new = ticketsNewCount;

  log('Verification results:', results);

  // Check if counts match (roughly)
  if (results.reviews.old > results.reviews.new) {
    log(`Reviews: ${results.reviews.old} old, ${results.reviews.new} new — some may not be migrated yet`);
  } else {
    log(`Reviews: ${results.reviews.old} old, ${results.reviews.new} new — looks good`);
  }

  if (results.notifications.old > results.notifications.new) {
    log(`Notifications: ${results.notifications.old} old, ${results.notifications.new} new — some may not be migrated yet`);
  } else {
    log(`Notifications: ${results.notifications.old} old, ${results.notifications.new} new — looks good`);
  }

  if (results.tickets.old > results.tickets.new) {
    log(`Tickets: ${results.tickets.old} old, ${results.tickets.new} new — some may not be migrated yet`);
  } else {
    log(`Tickets: ${results.tickets.old} old, ${results.tickets.new} new — looks good`);
  }

  return results;
}

// ========== MAIN MIGRATION FUNCTION ==========

async function runMigration() {
  const startTime = Date.now();

  log('========================================');
  log('STARTING SUB-COLLECTION MIGRATION');
  log(`DRY RUN: ${DRY_RUN}`);
  log('========================================');

  try {
    // Run migrations in sequence
    await migrateReviews();
    await migrateNotifications();
    await migrateTickets();
    await migrateFollowing();

    // Verify
    await verifyMigration();

    const endTime = Date.now();
    const duration = (endTime - startTime) / 1000;

    log('========================================');
    log('MIGRATION COMPLETE');
    log(`Duration: ${duration} seconds`);
    log(`DRY RUN: ${DRY_RUN}`);
    log('========================================');

    if (DRY_RUN) {
      log('⚠️  This was a DRY RUN. No data was modified.');
      log('To actually run the migration, remove the --dry-run flag.');
    }

  } catch (error) {
    logError('Migration failed', error);
  }
}

// ========== RUN THE MIGRATION ==========

runMigration();