// Firestore rules on the real rules engine. Run with: npm test (needs Java and
// the Firebase CLI). Uses a local emulator; it never touches the live project.
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, deleteField, doc, getDocs, query, serverTimestamp, setDoc, updateDoc, where, writeBatch, Timestamp,
} from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-agritrade',
  firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8085 },
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true, email: `${uid}@x.com` }).firestore();
const seed = () => env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/buyer'), { role: 'buyer', approvalStatus: 'approved', isVerified: true });
  await setDoc(doc(db, 'users/buyer2'), { role: 'buyer', approvalStatus: 'approved', isVerified: true });
  await setDoc(doc(db, 'users/farmer'), { role: 'farmer', approvalStatus: 'approved', isVerified: true, mustChangePassword: true });
  await setDoc(doc(db, 'users/farmer2'), { role: 'farmer', approvalStatus: 'approved', isVerified: true });
  await setDoc(doc(db, 'users/admin'), { role: 'admin', approvalStatus: 'approved', isVerified: true });
  await setDoc(doc(db, 'products/corn'), {
    farmerId: 'farmer', name: 'Corn', price: 50, retailPrice: 50, quantity: 100, isSuspended: false,
    wholesaleEnabled: true, wholesalePrice: 40, wholesaleMinimumQuantity: 10,
  });
  await setDoc(doc(db, 'products/oldrice'), { farmerId: 'farmer', name: 'Rice', price: 33.33, quantity: 100, isSuspended: false });
  await setDoc(doc(db, 'products/nowholesale'), {
    farmerId: 'farmer', name: 'Okra', price: 50, retailPrice: 50, quantity: 100, isSuspended: false,
    wholesaleEnabled: false, wholesalePrice: 40, wholesaleMinimumQuantity: 10,
  });
  const order = (status, buyerId = 'buyer', extra = {}) => ({
    buyerId, sellerId: 'farmer', productId: 'corn', productName: 'Corn', quantity: 2, status, ...extra,
  });
  await setDoc(doc(db, 'orders/pending1'), order('pending'));
  await setDoc(doc(db, 'orders/confirmed1'), order('confirmed'));
  await setDoc(doc(db, 'orders/done1'), order('completed'));
  await setDoc(doc(db, 'orders/done2'), { ...order('completed'), sellerId: 'farmer2' });
  await setDoc(doc(db, 'market_sales/s1'), { productName: 'Corn', pricePerUnit: 50, status: 'completed' });
  await setDoc(doc(db, 'searchEvents/e1'), { userId: 'buyer', query: 'corn' });
  await setDoc(doc(db, 'searchEvents/e2'), { userId: 'buyer2', query: 'rice' });
  await setDoc(doc(db, 'searchTrends/t1'), { term: 'corn', days: { '2026-11-01': 2 } });
  await setDoc(doc(db, 'conversations/c1'), { participants: ['buyer', 'farmer'] });
  await setDoc(doc(db, 'conversations/c1/messages/m1'), { senderId: 'farmer', text: 'Hello' });
});

// The same two writes as OrderService.createOrder made before stock was taken
// on confirmation (older app versions still do), in one commit.
function place(db, id, product, quantity, pricePerUnit, total, before = 100) {
  const batch = writeBatch(db);
  batch.update(doc(db, `products/${product}`), { quantity: before - quantity, lastOrderId: id });
  batch.set(doc(db, `orders/${id}`), {
    sellerId: 'farmer', buyerId: 'buyer', buyerName: 'Ana', buyerAddress: 'Laurel', productId: product,
    productName: 'Corn', quantity, unit: 'kg', pricingType: 'retail', pricePerUnit, unitPrice: pricePerUnit,
    subtotal: total, total, deliveryMethod: 'pickup', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  return batch.commit();
}
const cancel = (db, id, reason = 'buyer') => updateDoc(doc(db, `orders/${id}`), {
  status: 'cancelled', cancelReason: reason, cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
});

let passed = 0;
let failed = 0;
async function check(name, run) {
  await env.clearFirestore();
  await seed();
  try { await run(); passed += 1; console.log('ok  ', name); } catch (e) {
    failed += 1; console.log('FAIL', name, '-', String(e.message).slice(0, 200));
  }
}

const buyer = () => as('buyer');
const farmer = () => as('farmer');

await check('a retail order at the listing price is placed', () => assertSucceeds(place(buyer(), 'a1', 'corn', 3, 50, 150)));
await check('a decimal quantity at a decimal price is placed', () => assertSucceeds(place(buyer(), 'a2', 'oldrice', 2.5, 33.33, 2.5 * 33.33)));
await check('an older listing with only price is placed', () => assertSucceeds(place(buyer(), 'a3', 'oldrice', 3, 33.33, 3 * 33.33)));
await check('a wholesale order at the minimum is placed', () => assertSucceeds(place(buyer(), 'a4', 'corn', 10, 40, 400)));
await check('a retail price on a big order is still allowed', () => assertSucceeds(place(buyer(), 'a5', 'corn', 12, 50, 600)));
await check('a made-up low price is refused', () => assertFails(place(buyer(), 'b1', 'corn', 3, 1, 3)));
await check('a wrong total is refused', () => assertFails(place(buyer(), 'b2', 'corn', 3, 50, 3)));
await check('the wholesale price below the minimum is refused', () => assertFails(place(buyer(), 'b3', 'corn', 9, 40, 360)));
await check('the wholesale price with wholesale off is refused', () => assertFails(place(buyer(), 'b4', 'nowholesale', 20, 40, 800)));
await check('a zero price is refused', () => assertFails(place(buyer(), 'b5', 'corn', 3, 0, 0)));

await check('a buyer can cancel their pending order', () => assertSucceeds(cancel(buyer(), 'pending1')));
await check('a buyer cannot cancel once it is confirmed', () => assertFails(cancel(buyer(), 'confirmed1')));
await check('another buyer cannot cancel it', () => assertFails(cancel(as('buyer2'), 'pending1')));
await check('a buyer cannot cancel as "expired"', () => assertFails(cancel(buyer(), 'pending1', 'expired')));
await check('a cancel cannot change anything else', () => assertFails(updateDoc(doc(buyer(), 'orders/pending1'), {
  status: 'cancelled', cancelReason: 'buyer', cancelledAt: serverTimestamp(), quantity: 1,
})));

// The current app: placing an order leaves the listing alone, and the
// farmer's confirmation takes the stock (stockOnConfirm).
function placeNew(db, id, quantity, extra = {}) {
  return setDoc(doc(db, `orders/${id}`), {
    sellerId: 'farmer', buyerId: 'buyer', buyerName: 'Ana', buyerAddress: 'Laurel', productId: 'corn',
    productName: 'Corn', quantity, unit: 'kg', pricingType: 'retail', pricePerUnit: 50, unitPrice: 50,
    subtotal: 50 * quantity, total: 50 * quantity, deliveryMethod: 'pickup', status: 'pending',
    stockOnConfirm: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
  });
}
const seedNewPending = () => env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'orders/new1'), {
  buyerId: 'buyer', sellerId: 'farmer', productId: 'corn', productName: 'Corn', quantity: 2,
  status: 'pending', stockOnConfirm: true,
}));
// The same two writes as OrderService.updateStatus confirming, in one commit.
function confirmTaking(db, id, newQuantity) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'products/corn'), { quantity: newQuantity });
  batch.update(doc(db, `orders/${id}`), {
    status: 'confirmed', stockDeductedAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

await check('an order is placed without touching the listing\'s stock', () => assertSucceeds(placeNew(buyer(), 'n1', 3)));
await check('it cannot ask for more than the listing has', () => assertFails(placeNew(buyer(), 'n2', 101)));
await check('it cannot arrive marked as having taken stock', () => assertFails(placeNew(buyer(), 'n3', 3, { stockDeductedAt: serverTimestamp() })));
await check('confirming takes exactly its quantity off the listing', async () => {
  await seedNewPending();
  await assertSucceeds(confirmTaking(farmer(), 'new1', 98));
});
await check('confirming without taking the stock is refused', async () => {
  await seedNewPending();
  await assertFails(updateDoc(doc(farmer(), 'orders/new1'), { status: 'confirmed', updatedAt: serverTimestamp() }));
});
await check('confirming that takes the wrong amount is refused', async () => {
  await seedNewPending();
  await assertFails(confirmTaking(farmer(), 'new1', 99));
});
await check('an older order is confirmed as before, taking nothing again', () => assertSucceeds(
  updateDoc(doc(farmer(), 'orders/pending1'), { status: 'confirmed', updatedAt: serverTimestamp() }),
));
await check('shipping cannot touch the stock mark', () => assertFails(
  updateDoc(doc(farmer(), 'orders/confirmed1'), { status: 'shipped', stockDeductedAt: serverTimestamp(), updatedAt: serverTimestamp() }),
));

await check('a farmer cannot list every completed order', () => assertFails(getDocs(query(collection(farmer(), 'orders'), where('status', '==', 'completed')))));
await check('a farmer can list their own', () => assertSucceeds(getDocs(query(collection(farmer(), 'orders'), where('sellerId', '==', 'farmer')))));
await check('a farmer can read market_sales', () => assertSucceeds(getDocs(collection(farmer(), 'market_sales'))));

await check('a farmer cannot read who searched', () => assertFails(getDocs(collection(farmer(), 'searchEvents'))));
await check('a buyer cannot read other buyers', () => assertFails(getDocs(collection(buyer(), 'searchEvents'))));
await check('a buyer can read their own searches', () => assertSucceeds(getDocs(query(collection(buyer(), 'searchEvents'), where('userId', '==', 'buyer')))));
await check('the Admin can read searches for the heatmap', () => assertSucceeds(getDocs(collection(as('admin'), 'searchEvents'))));
await check('a farmer can read the anonymous trends', () => assertSucceeds(getDocs(collection(farmer(), 'searchTrends'))));

// Reactions held on a chat message: likes.{uid} is one of five emoji.
const react = (db, uid, value) => updateDoc(doc(db, 'conversations/c1/messages/m1'), { [`likes.${uid}`]: value });
await check('a participant can react with a heart', () => assertSucceeds(react(buyer(), 'buyer', 'heart')));
await check('each of the five reactions is allowed', async () => {
  for (const r of ['heart', 'like', 'wow', 'sad', 'angry']) await assertSucceeds(react(buyer(), 'buyer', r));
});
await check('a like from before reactions is still allowed', () => assertSucceeds(react(buyer(), 'buyer', true)));
await check('a made-up reaction is refused', () => assertFails(react(buyer(), 'buyer', 'laugh')));
await check('nobody sets another person\'s reaction', () => assertFails(react(buyer(), 'farmer', 'heart')));
await check('someone outside the chat cannot react', () => assertFails(react(as('buyer2'), 'buyer2', 'heart')));

await check('a farmer cannot clear mustChangePassword', () => assertFails(updateDoc(doc(farmer(), 'users/farmer'), { mustChangePassword: false })));
await check('a farmer can save their own farmerType', () => assertSucceeds(updateDoc(doc(farmer(), 'users/farmer'), { farmerType: 'Crop Farmer' })));
await check('a buyer can save their own buyerType', () => assertSucceeds(updateDoc(doc(buyer(), 'users/buyer'), { buyerType: 'Market Vendor' })));
await check('a registering buyer can save buyerType', () => assertSucceeds(setDoc(doc(as('newbuyer'), 'users/newbuyer'), {
  role: 'buyer', approvalStatus: 'approved', isVerified: true, buyerType: 'Reseller / Trader', createdAt: Timestamp.now(),
})));


// ---- the whole flow ----
const proposedDelay = () => ({
  reason: 'weather', note: '', proposedDate: Timestamp.fromDate(new Date('2026-12-01')),
  reportedAt: Timestamp.now(), status: 'proposed',
});
async function withOrder(id, fields) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'orders/' + id), {
    buyerId: 'buyer', sellerId: 'farmer', productId: 'corn', productName: 'Corn', quantity: 2, ...fields,
  }));
}
const step = (db, id, data) => updateDoc(doc(db, 'orders/' + id), { updatedAt: serverTimestamp(), ...data });

await check('farmer accepts a pending order', () => assertSucceeds(step(farmer(), 'pending1', { status: 'confirmed' })));
await check('farmer rejects a pending order', () => assertSucceeds(step(farmer(), 'pending1', { status: 'rejected' })));
await check('farmer ships a confirmed order', () => assertSucceeds(step(farmer(), 'confirmed1', { status: 'shipped' })));
const daysAgo = (days) => Timestamp.fromMillis(Date.now() - days * 24 * 60 * 60 * 1000);
const complete = (id) => step(farmer(), id, { status: 'completed', completedAt: serverTimestamp(), completedBy: 'farmer' });
const farmerCancel = (id, note, extra = {}) => updateDoc(doc(farmer(), 'orders/' + id), {
  status: 'cancelled', cancelReason: 'farmer', cancelNote: note, cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
});

await check('a farmer cannot complete before the buyer has had 3 days', async () => {
  await withOrder('s1', { status: 'shipped', shippedAt: daysAgo(1), updatedAt: daysAgo(1) });
  await assertFails(complete('s1'));
});
await check('a farmer can complete once the 3 days have passed', async () => {
  await withOrder('s1', { status: 'shipped', shippedAt: daysAgo(4), updatedAt: daysAgo(4) });
  await assertSucceeds(complete('s1'));
});
await check('a just-shipped order with no shippedAt yet still waits', async () => {
  await withOrder('s1', { status: 'shipped', updatedAt: daysAgo(0) });
  await assertFails(complete('s1'));
});
await check('a farmer cannot say the buyer completed it', async () => {
  await withOrder('s1', { status: 'shipped', shippedAt: daysAgo(4), updatedAt: daysAgo(4) });
  await assertFails(step(farmer(), 's1', { status: 'completed', completedAt: serverTimestamp(), completedBy: 'buyer' }));
});
await check('a farmer can cancel a confirmed order with a reason', () => assertSucceeds(farmerCancel('confirmed1', 'The harvest failed.')));
await check('a farmer cannot cancel without a reason', () => assertFails(farmerCancel('confirmed1', '')));
await check('a farmer cannot cancel a shipped order', async () => {
  await withOrder('s1', { status: 'shipped', shippedAt: daysAgo(1), updatedAt: daysAgo(1) });
  await assertFails(farmerCancel('s1', 'Changed my mind.'));
});
await check('another farmer cannot cancel it', () => assertFails(updateDoc(doc(as('farmer2'), 'orders/confirmed1'), {
  status: 'cancelled', cancelReason: 'farmer', cancelNote: 'x', cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
})));
await check('a cancel cannot change the price', () => assertFails(farmerCancel('confirmed1', 'Reason.', { total: 1 })));
await check('a buyer cannot cancel as the farmer', () => assertFails(updateDoc(doc(buyer(), 'orders/confirmed1'), {
  status: 'cancelled', cancelReason: 'farmer', cancelNote: 'x', cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
})));
await check('buyer confirms a shipped order', async () => {
  await withOrder('s2', { status: 'shipped' });
  await assertSucceeds(step(buyer(), 's2', { status: 'completed', completedAt: serverTimestamp(), completedBy: 'buyer' }));
});
await check('buyer edits a pending order', () => assertSucceeds(step(buyer(), 'pending1', { buyerName: 'Ana B' })));
await check('farmer reports a delay', () => assertSucceeds(updateDoc(doc(farmer(), 'orders/confirmed1'), {
  delay: { reason: 'weather', note: '', proposedDate: Timestamp.fromDate(new Date('2026-12-01')), reportedAt: serverTimestamp(), status: 'proposed' },
  updatedAt: serverTimestamp(),
})));
await check('buyer accepts the new date', async () => {
  const date = Timestamp.fromDate(new Date('2026-12-01'));
  const delay = { ...proposedDelay(), proposedDate: date };
  await withOrder('d1', { status: 'confirmed', delay });
  await assertSucceeds(step(buyer(), 'd1', { delay: { ...delay, status: 'accepted' }, confirmedFulfillmentDate: date }));
});
await check('buyer cancels after a delay', async () => {
  await withOrder('d2', { status: 'confirmed', delay: proposedDelay() });
  await assertSucceeds(cancel(buyer(), 'd2', 'delay'));
});

// Review likes: another buyer sets or clears only their own like.
const seedReview = () => env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'productReviews/done1'), {
  buyerId: 'buyer', orderId: 'done1', productId: 'corn', sellerId: 'farmer', rating: 4, comment: 'okay',
}));
const review = (db) => doc(db, 'productReviews/done1');
await check('another buyer likes a review', async () => {
  await seedReview();
  await assertSucceeds(updateDoc(review(as('buyer2')), { 'likes.buyer2': true }));
});
await check('another buyer takes the like back', async () => {
  await seedReview();
  await assertSucceeds(updateDoc(review(as('buyer2')), { 'likes.buyer2': true }));
  await assertSucceeds(updateDoc(review(as('buyer2')), { 'likes.buyer2': deleteField() }));
});
await check('a buyer cannot like their own review', async () => {
  await seedReview();
  await assertFails(updateDoc(review(buyer()), { 'likes.buyer': true }));
});
await check('a buyer cannot like for someone else', async () => {
  await seedReview();
  await assertFails(updateDoc(review(as('buyer2')), { 'likes.buyer3': true }));
});
await check('a like is only true', async () => {
  await seedReview();
  await assertFails(updateDoc(review(as('buyer2')), { 'likes.buyer2': 5 }));
});
await check('a like cannot change the rating too', async () => {
  await seedReview();
  await assertFails(updateDoc(review(as('buyer2')), { 'likes.buyer2': true, rating: 1 }));
});
await check('a farmer cannot like a review', async () => {
  await seedReview();
  await assertFails(updateDoc(review(as('farmer2')), { 'likes.farmer2': true }));
});

// Review photos: up to three, on the buyer's own review.
const pics = (n) => Array.from({ length: n }, (_, i) => `https://res.cloudinary.com/x/r${i}.jpg`);
await check('the buyer edits their review with three photos', async () => {
  await seedReview();
  await assertSucceeds(updateDoc(review(buyer()), { imageUrls: pics(3), imageUrl: pics(3)[0] }));
});
await check('a review cannot carry four photos', async () => {
  await seedReview();
  await assertFails(updateDoc(review(buyer()), { imageUrls: pics(4) }));
});

// An order placed from the chat: its card, from that order's buyer only.
const orderCard = (db, sender, orderId, id = 'order_' + orderId) =>
  setDoc(doc(db, `conversations/c1/messages/${id}`), {
    senderId: sender, type: 'orderPlaced', orderId, productName: 'Corn', createdAt: serverTimestamp(),
  });
await check('the buyer posts the card of their order in the chat', () =>
  assertSucceeds(orderCard(buyer(), 'buyer', 'pending1')));
await check('the farmer cannot post an order card', () =>
  assertFails(orderCard(farmer(), 'farmer', 'pending1')));
await check("a buyer cannot post the card of another buyer's order", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'conversations/c2'), { participants: ['buyer2', 'farmer'] }));
  await assertFails(setDoc(doc(as('buyer2'), 'conversations/c2/messages/order_pending1'), {
    senderId: 'buyer2', type: 'orderPlaced', orderId: 'pending1', createdAt: serverTimestamp(),
  }));
});
await check('an order card only under its own id', () =>
  assertFails(orderCard(buyer(), 'buyer', 'pending1', 'somethingElse')));

console.log(`\n${passed} passed, ${failed} failed`);
await env.cleanup();
process.exit(failed ? 1 : 0);
