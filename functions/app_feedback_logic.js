/**
 * Checks app feedback before it is emailed to the AgriTrade+ team
 * (see app_feedback.js). No Firebase in here, so it can be unit tested
 * (see test/app_feedback_logic.test.js).
 */

const MESSAGE_MAX = 1000;

// At most this many feedback emails from one person a day, so the team's
// inbox (and Gmail's daily sending limit) cannot be flooded.
const DAILY_LIMIT = 5;

// What the farmer or buyer had just done when the app asked; "menu" when
// they opened Send Feedback themselves.
const TRIGGERS = {
  menu: "Opened Send Feedback",
  product_posted: "Asked after posting a product",
  order_placed: "Asked after placing an order",
};

/**
 * The cleaned feedback, or `{ error }`:
 *
 *  - rating: 1–5 stars, required
 *  - message: optional, up to MESSAGE_MAX characters
 *  - trigger: one of TRIGGERS (anything else counts as "menu")
 *  - platform, appVersion: short labels for the email, if given
 */
function checkFeedback(input) {
  const data = input || {};
  const rating = Number(data.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    return { error: "Choose a rating from 1 to 5 stars." };
  }
  const message = typeof data.message === "string" ? data.message.trim() : "";
  if (message.length > MESSAGE_MAX) {
    return { error: `Feedback can be at most ${MESSAGE_MAX} characters.` };
  }
  const label = (value) => (typeof value === "string" ? value.trim().slice(0, 40) : "");
  return {
    rating,
    message,
    trigger: Object.hasOwn(TRIGGERS, data.trigger) ? data.trigger : "menu",
    platform: label(data.platform),
    appVersion: label(data.appVersion),
  };
}

// The day, in Philippine time, a send counts toward: "2026-10-26".
function feedbackDay(now = Date.now()) {
  return new Date(now + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** Whether one more send is allowed, given `throttle` = { day, count }. */
function underDailyLimit(throttle, day) {
  if (!throttle || throttle.day !== day) return true;
  return (Number(throttle.count) || 0) < DAILY_LIMIT;
}

module.exports = { MESSAGE_MAX, DAILY_LIMIT, TRIGGERS, checkFeedback, feedbackDay, underDailyLimit };
