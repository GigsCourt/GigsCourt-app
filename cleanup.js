const admin = require('firebase-admin');
const fs = require('fs');

// Read the service account file manually
const serviceAccountPath = './functions/serviceAccountKey.json';
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account file not found at:', serviceAccountPath);
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

// Initialize with the credential
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

console.log('Starting cleanup...');

async function deleteAll() {
  try {
    // 1. Delete all Auth users
    console.log('Deleting Auth users...');
    try {
      const listUsers = await auth.listUsers();
      const uids = listUsers.users.map(user => user.uid);
      if (uids.length > 0) {
        await auth.deleteUsers(uids);
        console.log(`Deleted ${uids.length} users`);
      } else {
        console.log('No users to delete');
      }
    } catch (err) {
      console.log('Auth deletion skipped:', err.message);
    }

    // 2. Delete all Firestore collections
    console.log('Deleting Firestore collections...');
    const collections = ['users', 'chats', 'reviews', 'notifications', 'tickets', 'stats', 'config', 'admin_emails', 'transactions'];
    
    for (const col of collections) {
      try {
        console.log(`Deleting ${col}...`);
        const snapshot = await db.collection(col).get();
        if (snapshot.empty) {
          console.log(`  ${col} is empty`);
          continue;
        }
        const batch = db.batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
        console.log(`  Deleted ${snapshot.size} documents from ${col}`);
      } catch (err) {
        console.log(`  Error deleting ${col}:`, err.message);
      }
    }

    console.log('✅ Cleanup complete!');
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

deleteAll();