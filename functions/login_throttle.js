/**
 * Failed-login cooldown for email/password sign-in: after 5 wrong passwords
 * in a row, password login for that email is paused for 5 minutes.
 *
 *   checkLoginAllowed    callable, no sign-in   — is this email paused?
 *   reportLoginFailure   callable, no sign-in   — count one wrong password
 *   clearLoginFailures   callable, signed-in    — reset after a good login
 *
 * Firebase Authentication still checks the password and owns the account;
 * nothing here disables or changes an account. The count and the pause
 * live in loginThrottles/{hash of the email}, written only through the
 * Admin SDK (firestore.rules gives clients no access), so they follow the
 * email, not the device: restarting the app, clearing its storage or
 * switching phones does not reset them.
 *
 * reportLoginFailure looks the email up in Firebase Auth and says when it
 * has no account (or only Google sign-in), so the app can tell the person
 * plainly; an unknown email is not counted. This tells a caller whether an
 * email is registered — accepted by the user (2026-11-05) for clearer login
 * messages.
 * checkLoginAllowed still answers the same for every email.
 *
 * What this cannot do: the app reports its own failed attempts, so someone
 * calling Firebase's sign-in API directly, outside the app, is not counted
 * here — that traffic is limited only by Firebase Authentication's own
 * abuse protection (the too-many-requests error).
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const throttle = require("./login_throttle_logic");

const db = getFirestore();

const REGION = "asia-southeast1";

const throttles = db.collection("loginThrottles");

// What Firebase Authentication knows of [email]: registered, and whether
// it has a password (a Google-only account has none). Unknown (null) when
// the lookup itself fails, so the app falls back to its usual message.
async function accountFor(email) {
  try {
    const user = await getAuth().getUserByEmail(email);
    const providers = (user.providerData || []).map((p) => p.providerId);
    return { registered: true, passwordless: !providers.includes("password") };
  } catch (e) {
    if (e && e.code === "auth/user-not-found") return { registered: false, passwordless: false };
    return { registered: null, passwordless: false };
  }
}

function emailFrom(request) {
  const email = throttle.normalizeEmail(request.data && request.data.email);
  if (!email) throw new HttpsError("invalid-argument", "Enter a valid email address.");
  return email;
}

exports.checkLoginAllowed = onCall({ region: REGION }, async (request) => {
  const email = emailFrom(request);
  const snap = await throttles.doc(throttle.keyFor(email)).get();
  return throttle.status(snap.exists ? snap.data() : null, Date.now());
});

exports.reportLoginFailure = onCall({ region: REGION }, async (request) => {
  const email = emailFrom(request);
  // Whether the email has an account, and whether it can sign in with a
  // password, so the app can say "not registered" or "use Google" instead
  // of "incorrect email or password" (decided by the user, 2026-11-05). An
  // unknown email is not counted towards the pause.
  const account = await accountFor(email);
  if (account.registered === false) {
    return { locked: false, attemptsRemaining: null, registered: false };
  }
  if (account.passwordless) {
    return { locked: false, attemptsRemaining: null, registered: true, passwordless: true };
  }
  const ref = throttles.doc(throttle.keyFor(email));
  // One transaction, so attempts arriving together are each counted once.
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const { next, result } = throttle.recordFailure(snap.exists ? snap.data() : null, now);
    if (next) {
      tx.set(ref, {
        failedCount: next.failedCount,
        lastFailedAt: Timestamp.fromMillis(next.lastFailedAt),
        lockedUntil: next.lockedUntil ? Timestamp.fromMillis(next.lockedUntil) : null,
      });
    }
    return result;
  });
});

// The email comes from the caller's own Firebase session, never from the
// request, so one account cannot clear another's count.
exports.clearLoginFailures = onCall({ region: REGION }, async (request) => {
  const email = throttle.normalizeEmail(request.auth && request.auth.token && request.auth.token.email);
  if (!email) throw new HttpsError("unauthenticated", "Please log in again.");
  await throttles.doc(throttle.keyFor(email)).delete();
  return { ok: true };
});
