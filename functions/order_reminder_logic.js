/**
 * When to remind a farmer to mark a shipped order Completed
 * (remindFarmersToComplete in index.js): the day after the order's date
 * has passed — the date both sides agreed on (after a delay), else the
 * date the buyer asked for, else the day it was shipped — while it is
 * still "shipped" and has not been reminded yet. Pure functions, so they
 * are tested without Firebase.
 */

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

// The calendar day (in the Philippines) of an instant, as a day number.
function manilaDay(ms) {
  return Math.floor((ms + MANILA_OFFSET_MS) / (24 * 60 * 60 * 1000));
}

/** The date the order was due to reach the buyer, in ms, or null. */
function dueDateMs(order) {
  return millis(order.confirmedFulfillmentDate) ??
    millis(order.requestedFulfillmentDate) ??
    millis(order.neededBy) ??
    millis(order.shippedAt) ??
    millis(order.updatedAt);
}

// How long the buyer has to confirm a shipped order before the farmer may
// complete it. The same period as firestore.rules and kBuyerConfirmWindow.
const BUYER_CONFIRM_DAYS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

// From the day after the due date (Philippine calendar days).
function pastDueDate(order, nowMs) {
  const due = dueDateMs(order);
  return due != null && manilaDay(nowMs) > manilaDay(due);
}

/** Whether the buyer should be asked to confirm [order] at [nowMs]. */
function receivedReminderDue(order, nowMs) {
  if (!order || order.status !== "shipped") return false;
  return !order.receivedReminderSentAt && pastDueDate(order, nowMs);
}

/**
 * Whether the farmer should get the completion reminder at [nowMs]: only
 * once they are allowed to complete it, the buyer having not answered.
 */
function completionReminderDue(order, nowMs) {
  if (!order || order.status !== "shipped") return false;
  if (order.completionReminderSentAt) return false;
  const shipped = millis(order.shippedAt) ?? millis(order.updatedAt);
  if (shipped == null || nowMs < shipped + BUYER_CONFIRM_DAYS * DAY_MS) return false;
  return pastDueDate(order, nowMs);
}

// How long a farmer has to answer a new order.
const PENDING_ORDER_DAYS = 3;

/**
 * Whether a pending order has gone unanswered long enough to cancel it
 * (expirePendingOrders in index.js).
 */
function pendingOrderExpired(order, nowMs) {
  if (!order || order.status !== "pending") return false;
  const placed = millis(order.createdAt);
  return placed != null && nowMs - placed >= PENDING_ORDER_DAYS * 24 * 60 * 60 * 1000;
}

module.exports = {
  dueDateMs, completionReminderDue, receivedReminderDue, manilaDay, pendingOrderExpired,
  PENDING_ORDER_DAYS, BUYER_CONFIRM_DAYS,
};
