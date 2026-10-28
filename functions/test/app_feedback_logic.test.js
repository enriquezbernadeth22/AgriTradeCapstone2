// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const logic = require("../app_feedback_logic");
const templates = require("../email_templates");

test("feedback needs a 1–5 star rating; the comment is optional", () => {
  assert.ok(logic.checkFeedback({ rating: 0 }).error);
  assert.ok(logic.checkFeedback({ rating: 6 }).error);
  assert.ok(logic.checkFeedback({ rating: 3.5 }).error);
  assert.ok(logic.checkFeedback({}).error);
  const ok = logic.checkFeedback({ rating: 4, message: "  Ang ganda!  " });
  assert.strictEqual(ok.rating, 4);
  assert.strictEqual(ok.message, "Ang ganda!");
  assert.strictEqual(logic.checkFeedback({ rating: 5 }).message, "");
});

test("a comment over the limit is refused", () => {
  assert.ok(logic.checkFeedback({ rating: 5, message: "x".repeat(logic.MESSAGE_MAX + 1) }).error);
  assert.ok(!logic.checkFeedback({ rating: 5, message: "x".repeat(logic.MESSAGE_MAX) }).error);
});

test("an unknown trigger counts as the menu", () => {
  assert.strictEqual(logic.checkFeedback({ rating: 5, trigger: "order_placed" }).trigger, "order_placed");
  assert.strictEqual(logic.checkFeedback({ rating: 5, trigger: "anything" }).trigger, "menu");
  assert.strictEqual(logic.checkFeedback({ rating: 5, trigger: "__proto__" }).trigger, "menu");
});

test("at most DAILY_LIMIT a day, counted in Philippine time", () => {
  const day = logic.feedbackDay(Date.UTC(2026, 9, 25, 17, 0)); // 1 AM on the 26th in Manila
  assert.strictEqual(day, "2026-10-26");
  assert.ok(logic.underDailyLimit(null, day));
  assert.ok(logic.underDailyLimit({ day, count: logic.DAILY_LIMIT - 1 }, day));
  assert.ok(!logic.underDailyLimit({ day, count: logic.DAILY_LIMIT }, day));
  // A new day starts over.
  assert.ok(logic.underDailyLimit({ day: "2026-10-25", count: 99 }, day));
});

test("the team's email shows the rating, who sent it and why it was asked", () => {
  const mail = templates.appFeedbackEmail({
    rating: 4,
    message: "Sana may <dark mode>.",
    triggerLabel: logic.TRIGGERS.order_placed,
    name: "Ana Go",
    email: "ana@gmail.com",
    role: "Buyer",
    barangay: "Gulod",
    platform: "android",
    appVersion: "1.0.0",
  });
  assert.strictEqual(mail.subject, "App feedback: 4/5 from Ana Go (Buyer)");
  assert.ok(mail.text.includes("★★★★☆"));
  assert.ok(mail.text.includes("Asked after placing an order"));
  assert.ok(mail.text.includes("Sana may <dark mode>."));
  assert.ok(mail.html.includes("Sana may &lt;dark mode&gt;."));
  assert.ok(!mail.html.includes("<dark mode>"));
});
