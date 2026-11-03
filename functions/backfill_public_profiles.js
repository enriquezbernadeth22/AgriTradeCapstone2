// One-time migration for profiles that existed before syncPublicProfile was
// deployed. Run from an authenticated environment with Firebase Admin ADC:
//   node functions/backfill_public_profiles.js
// This reads only the users collection and writes the same allow-listed
// projection as syncPublicProfile (public_profile_logic.js); run it again
// after that list changes, so older profiles get the new fields too.
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (!getApps().length) initializeApp();
const db = getFirestore();
const { publicProfileOf } = require("./public_profile_logic");

async function main() {
  let cursor = null;
  let total = 0;
  while (true) {
    let query = db.collection("users").orderBy("__name__").limit(400);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      batch.set(db.collection("publicProfiles").doc(doc.id), publicProfileOf(doc.data()));
    }
    await batch.commit();
    total += page.size;
    cursor = page.docs[page.docs.length - 1];
  }
  process.stdout.write(`Updated ${total} public profile projections.\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
