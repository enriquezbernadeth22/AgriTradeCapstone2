/**
 * sendAppFeedback — callable, signed-in farmers and buyers.
 *
 * Feedback from the app (Profile → Send Feedback, or the prompt after a
 * few products posted or orders placed) goes by email to the AgriTrade+
 * team's inbox, with Reply-To set to the sender so the team can answer
 * straight from Gmail. The feedback itself is not kept in Firestore; only
 * a small per-person daily count (feedbackThrottles/{uid}, no client
 * access) limits how many can be sent.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const { TRIGGERS, checkFeedback, feedbackDay, underDailyLimit } = require("./app_feedback_logic");

const db = getFirestore();

// The team's inbox: the same Gmail account the app's email is sent from,
// and the support email the app shows (lib/data/mobile_faqs.dart).
const TEAM_INBOX = "agritrade.team@gmail.com";

exports.sendAppFeedback = onCall(
  { region: "asia-southeast1", secrets: MAIL_SECRETS },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Log in to send feedback.");
    }
    const feedback = checkFeedback(request.data);
    if (feedback.error) throw new HttpsError("invalid-argument", feedback.error);

    const uid = request.auth.uid;
    const snap = await db.collection("users").doc(uid).get();
    const profile = snap.exists ? snap.data() : {};
    const role = profile.role === "farmer" ? "Farmer" : profile.role === "buyer" ? "Buyer" : "";
    if (!role) throw new HttpsError("permission-denied", "Only farmers and buyers can send feedback here.");

    // Counted before sending, so a burst of taps cannot slip past it.
    const day = feedbackDay();
    const throttleRef = db.collection("feedbackThrottles").doc(uid);
    const allowed = await db.runTransaction(async (tx) => {
      const current = (await tx.get(throttleRef)).data();
      if (!underDailyLimit(current, day)) return false;
      const count = current && current.day === day ? (Number(current.count) || 0) + 1 : 1;
      tx.set(throttleRef, { day, count });
      return true;
    });
    if (!allowed) {
      throw new HttpsError("resource-exhausted", "You have sent a lot of feedback today. Please try again tomorrow.");
    }

    const email = request.auth.token.email || profile.email || "";
    const name = profile.fullName || profile.name || request.auth.token.name || "";
    const mail = templates.appFeedbackEmail({
      ...feedback,
      triggerLabel: TRIGGERS[feedback.trigger],
      name,
      email,
      role,
      barangay: profile.barangay || "",
    });
    try {
      await sendMail(TEAM_INBOX, { ...mail, replyTo: email || undefined });
    } catch (err) {
      console.error("sendAppFeedback: email failed:", describeMailError(err));
      throw new HttpsError("unavailable", "Your feedback could not be sent. Please try again.");
    }
    return { sent: true };
  }
);
