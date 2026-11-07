// One-time clean-up for commodities the Admin removed from Price Management
// (deleted their market_prices record) before onCommodityRemoved was
// deployed (2026-11-07): their listings stayed on the marketplace. This
// hides those listings the same way (isSuspended, COMMODITY_ARCHIVED) and
// leaves each farmer the same in-app notice. (No push: these are old.)
//
// Run from an authenticated environment with Firebase Admin ADC:
//   node functions/backfill_removed_commodities.js           (only lists)
//   node functions/backfill_removed_commodities.js --apply   (writes)
//
// A listing counts as removed when the Admin has commodities on record and
// its commodity (or, for older listings, its name) is not one of them. With
// no records at all the app uses its starting list, so nothing is touched.
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { COMMODITY_ARCHIVED, commodityNotice } = require("./commodity_notice");
const { categoryOf, deliveryChannels } = require("./notification_policy");

if (!getApps().length) initializeApp();
const db = getFirestore();
const apply = process.argv.includes("--apply");

async function main() {
  const records = await db.collection("market_prices").get();
  const onRecord = new Set(
    records.docs
      .map((doc) => String(doc.data().name || "").trim().toLowerCase())
      .filter(Boolean)
  );
  if (onRecord.size === 0) {
    process.stdout.write("No commodities on record: nothing to do.\n");
    return;
  }

  const products = await db.collection("products").get();
  // farmerId -> commodity name -> listing count
  const byFarmer = new Map();
  const hide = [];
  for (const doc of products.docs) {
    const product = doc.data();
    if (product.isSuspended === true || product.isArchived === true) continue;
    const commodity = String(product.commodity || product.name || "").trim();
    if (!commodity || onRecord.has(commodity.toLowerCase())) continue;
    hide.push({ doc, commodity });
    const farmerId = String(product.farmerId || "");
    if (!farmerId) continue;
    const counts = byFarmer.get(farmerId) || new Map();
    counts.set(commodity, (counts.get(commodity) || 0) + 1);
    byFarmer.set(farmerId, counts);
  }

  for (const { doc, commodity } of hide) {
    process.stdout.write(`${apply ? "Hiding" : "Would hide"} ${doc.id} (${commodity})\n`);
  }
  if (!apply) {
    process.stdout.write(
      `${hide.length} listing(s) of removed commodities, ${byFarmer.size} farmer(s). ` +
        "Run again with --apply to hide them and notify the farmers.\n"
    );
    return;
  }

  let batch = db.batch();
  let writes = 0;
  for (const { doc } of hide) {
    batch.update(doc.ref, {
      isSuspended: true,
      moderationStatus: COMMODITY_ARCHIVED,
      moderationReason: "",
      moderatedAt: FieldValue.serverTimestamp(),
    });
    if (++writes % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (writes % 400 !== 0) await batch.commit();

  let notified = 0;
  for (const [farmerId, counts] of byFarmer) {
    const farmer = await db.collection("users").doc(farmerId).get();
    if (!farmer.exists || farmer.data().accountStatus === "banned") continue;
    for (const [name, listings] of counts) {
      const notice = commodityNotice({ change: "removed", name, reason: "", listings });
      const id = `commodity_removed_backfill_${name.toLowerCase().replace(/[^a-z0-9]+/g, "_")}`;
      const item = db.collection("notifications").doc(farmerId).collection("items").doc(id);
      if ((await item.get()).exists) continue;
      await item.set({
        recipientId: farmerId,
        title: notice.title,
        body: notice.body,
        type: "announcement",
        category: categoryOf("announcement"),
        relatedId: null,
        data: { kind: "commodity", change: "removed", title: notice.title, body: notice.body },
        read: false,
        deliveryChannels: deliveryChannels("announcement", { pushed: false }),
        createdAt: FieldValue.serverTimestamp(),
      });
      notified++;
    }
  }
  process.stdout.write(`Hid ${writes} listing(s); left ${notified} notice(s).\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
