// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const {
  completionReminderDue, receivedReminderDue, pendingOrderExpired,
} = require("../order_reminder_logic");

// 9 AM Philippine time on a given October 2026 day.
const at9 = (day) => Date.UTC(2026, 9, day, 1, 0, 0);
const ts = (ms) => ({ toMillis: () => ms });

test("reminded the day after the order's date, not before", () => {
  const order = { status: "shipped", requestedFulfillmentDate: ts(at9(17)) };
  assert.strictEqual(receivedReminderDue(order, at9(17)), false);
  assert.strictEqual(receivedReminderDue(order, at9(18)), true);
});

test("an agreed new date wins over the requested one", () => {
  const order = {
    status: "shipped",
    requestedFulfillmentDate: ts(at9(15)),
    confirmedFulfillmentDate: ts(at9(20)),
  };
  assert.strictEqual(receivedReminderDue(order, at9(18)), false);
  assert.strictEqual(receivedReminderDue(order, at9(21)), true);
});

test("no date: counted from the day it was shipped", () => {
  const order = { status: "shipped", shippedAt: ts(at9(16)) };
  assert.strictEqual(receivedReminderDue(order, at9(16)), false);
  assert.strictEqual(receivedReminderDue(order, at9(17)), true);
});

test("only once, and only while shipped", () => {
  const due = { requestedFulfillmentDate: ts(at9(10)) };
  assert.strictEqual(
    completionReminderDue({ ...due, status: "shipped", completionReminderSentAt: ts(at9(11)) }, at9(18)),
    false
  );
  assert.strictEqual(completionReminderDue({ ...due, status: "completed" }, at9(18)), false);
  assert.strictEqual(completionReminderDue({ ...due, status: "confirmed" }, at9(18)), false);
});

test("a pending order is cancelled after 3 days without an answer", () => {
  const order = { status: "pending", createdAt: ts(at9(10)) };
  assert.strictEqual(pendingOrderExpired(order, at9(12)), false);
  assert.strictEqual(pendingOrderExpired(order, at9(13)), true);
});

test("an answered order, or one with no date, is left alone", () => {
  assert.strictEqual(pendingOrderExpired({ status: "confirmed", createdAt: ts(at9(1)) }, at9(20)), false);
  assert.strictEqual(pendingOrderExpired({ status: "pending" }, at9(20)), false);
  assert.strictEqual(pendingOrderExpired(undefined, at9(20)), false);
});

test("the buyer is asked first, the day after the order's date", () => {
  const order = { status: "shipped", shippedAt: ts(at9(10)) };
  assert.strictEqual(receivedReminderDue(order, at9(10)), false);
  assert.strictEqual(receivedReminderDue(order, at9(11)), true);
  assert.strictEqual(receivedReminderDue({ ...order, receivedReminderSentAt: ts(at9(11)) }, at9(12)), false);
});

test("the farmer is reminded only once they may complete it", () => {
  const order = { status: "shipped", shippedAt: ts(at9(10)) };
  assert.strictEqual(completionReminderDue(order, at9(12)), false);
  assert.strictEqual(completionReminderDue(order, at9(13)), true);
});
