/**
 * Admin Portal → User Accounts → Add Farmer.
 *
 *   adminCreateFarmer        callable, active Admin only: asks the farmer
 *   adminCancelFarmerInvite  callable, active Admin only
 *   confirmFarmerAccount     the page the farmer's email links to
 *   expireFarmerInvites      scheduled: ends invites not confirmed in time
 *
 * The agricultural office adds a farmer it has already verified in person,
 * but the account is created only once the farmer confirms it is them:
 *
 *  1. adminCreateFarmer checks the details, makes the login — disabled, with
 *     the password the Admin set (by the app's password rules), so the
 *     password is never stored or emailed by AgriTrade+ — and keeps the
 *     rest as an invite, farmerInvites/{inviteId}. The farmer is emailed
 *     the details with a "Yes, it's me" button (farmer_invite_logic.js).
 *     The Admin Portal watches the invite and shows that it is waiting.
 *  2. On the page, "Yes, it's me" creates the account already approved,
 *     like one an Admin approved in the Verification Queue (same fields —
 *     see verification_queue_view.dart), switches the login on, logs
 *     CREATE_FARMER_ACCOUNT in the Audit Log and emails the farmer that the
 *     account is ready, with a link to change the password (the AgriTrade+
 *     reset page, see reset_link.js). "No, it's not me" removes the login.
 *  3. An invite not answered within 24 hours, or cancelled by the Admin,
 *     ends the same way as "No": nothing is created.
 *
 * The farmer's agreement to the Terms and Privacy Policy, taken by the
 * office, is recorded as given there.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail } = require("./mailer");
const templates = require("./email_templates");
const { resetPageLink } = require("./reset_link");
const { signedInBeforeRevocation } = require("./admin_session_logic");
const { parseUserAgent } = require("./user_agent");
const { checkFarmerDetails } = require("./admin_create_farmer_logic");
const {
  INVITE_TTL_MS, STATUS, newInviteToken, hashToken, confirmLink, inviteState, renderInvitePage,
} = require("./farmer_invite_logic");

const db = getFirestore();
const REGION = "asia-southeast1";
const invites = () => db.collection("farmerInvites");

// The same check as logAuditEvent (index.js): a signed-in, active Admin
// whose session was not ended from Active Sessions.
async function activeAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Log in as an Admin first.");
  }
  const snap = await db.collection("users").doc(request.auth.uid).get();
  const profile = snap.exists ? snap.data() : {};
  const unverifiedAdminAccount = request.auth.token.email === "admin@agritrade.com";
  if ((request.auth.token.email_verified !== true && !unverifiedAdminAccount) ||
      profile.role !== "admin" ||
      (profile.accountStatus || "active") !== "active" ||
      signedInBeforeRevocation(request.auth.token.auth_time, profile.sessionsValidAfter)) {
    throw new HttpsError("permission-denied", "Only an active Admin can add a farmer account.");
  }
  return {
    uid: request.auth.uid,
    email: request.auth.token.email || null,
    name: request.auth.token.name || profile.name || profile.fullName || request.auth.token.email || "Admin",
  };
}

// Removes the disabled login an invite made — only while it is still
// that: disabled, with no account behind it.
async function releaseInviteLogin(uid) {
  if (!uid) return;
  try {
    const [user, profile] = await Promise.all([
      getAuth().getUser(uid),
      db.collection("users").doc(uid).get(),
    ]);
    if (user.disabled && !profile.exists) await getAuth().deleteUser(uid);
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      console.error(`releaseInviteLogin(${uid}) failed:`, err.message);
    }
  }
}

// Ends an invite still waiting (as `status`) and removes its login.
async function closeInvite(ref, status) {
  const closed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== STATUS.pending) return null;
    tx.update(ref, { status, closedAt: FieldValue.serverTimestamp() });
    return snap.data();
  });
  if (closed) await releaseInviteLogin(closed.uid);
  return closed;
}

exports.adminCreateFarmer = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const admin = await activeAdmin(request);
    const details = checkFarmerDetails(request.data);
    if (details.error) throw new HttpsError("invalid-argument", details.error);
    const {
      firstName, lastName, fullName, email, mobileNumber, barangay, rsbaNumber,
      password, termsVersion, privacyVersion,
    } = details;

    // Asking again replaces an earlier invite for this email still waiting.
    const earlier = await invites().where("email", "==", email).get();
    for (const doc of earlier.docs) {
      if (doc.data().status === STATUS.pending) await closeInvite(doc.ref, STATUS.cancelled);
    }

    // One account per email, as in registration.
    try {
      await getAuth().getUserByEmail(email);
      throw new HttpsError("already-exists", "This email already has an AgriTrade+ account.");
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      if (err.code !== "auth/user-not-found") {
        throw new HttpsError("unavailable", "Could not check the email. Try again.");
      }
    }

    // The login, with the password the Admin set, switched off until the
    // farmer confirms.
    let user;
    try {
      user = await getAuth().createUser({
        email,
        password,
        displayName: fullName,
        emailVerified: false,
        disabled: true,
      });
    } catch (err) {
      if (err.code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "This email already has an AgriTrade+ account.");
      }
      console.error("adminCreateFarmer: createUser failed:", err.message);
      throw new HttpsError("internal", "Could not create the account. Try again.");
    }

    const ua = (request.rawRequest && request.rawRequest.get("user-agent")) || "";
    const { browser, os } = parseUserAgent(ua);
    const location = typeof request.data.location === "string" && request.data.location.trim()
      ? request.data.location.trim().slice(0, 120)
      : "Unknown";
    const token = newInviteToken();
    const ref = invites().doc();
    try {
      await ref.set({
        status: STATUS.pending,
        tokenHash: hashToken(token),
        uid: user.uid,
        firstName,
        lastName,
        fullName,
        email,
        mobileNumber,
        barangay,
        rsbaNumber,
        ...(termsVersion ? { termsVersion } : {}),
        ...(privacyVersion ? { privacyVersion } : {}),
        invitedBy: { uid: admin.uid, email: admin.email, name: admin.name },
        device: { browser, os },
        ip: (request.rawRequest && request.rawRequest.ip) || null,
        location,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + INVITE_TTL_MS),
      });
    } catch (err) {
      await getAuth().deleteUser(user.uid).catch(() => {});
      console.error("adminCreateFarmer: invite write failed:", err.message);
      throw new HttpsError("internal", "Could not save the farmer's details. Try again.");
    }

    // Without the email the farmer cannot confirm, so nothing is kept.
    try {
      await sendMail(email, templates.farmerConfirmAccountEmail({
        name: fullName,
        link: confirmLink(ref.id, token),
        details: [
          ["Name", fullName],
          ["Email", email],
          ["Mobile", mobileNumber],
          ["Barangay", `${barangay}, Laurel, Batangas`],
          ["RSBSA number", rsbaNumber],
        ],
      }));
    } catch (err) {
      console.error(`adminCreateFarmer(${user.uid}) email failed:`, err.message);
      await ref.delete().catch(() => {});
      await getAuth().deleteUser(user.uid).catch(() => {});
      throw new HttpsError(
        "unavailable",
        "The confirmation email could not be sent to the farmer, so nothing was added. Check the email address and try again."
      );
    }
    return { inviteId: ref.id };
  }
);

exports.adminCancelFarmerInvite = onCall({ region: REGION }, async (request) => {
  await activeAdmin(request);
  const id = request.data && request.data.inviteId;
  if (typeof id !== "string" || !/^[A-Za-z0-9]{1,40}$/.test(id)) {
    throw new HttpsError("invalid-argument", "No such request.");
  }
  const closed = await closeInvite(invites().doc(id), STATUS.cancelled);
  return { cancelled: closed != null };
});

// Switches on the confirmed farmer's login; noted on the invite, so a
// failure is retried the next time the page is opened.
async function enableLogin(ref, uid) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await getAuth().updateUser(uid, { disabled: false });
      await ref.update({ loginEnabled: true });
      return true;
    } catch (err) {
      console.error(`confirmFarmerAccount: enabling ${uid} failed:`, err.message);
    }
  }
  return false;
}

// "Yes, it's me": the account, exactly as Add Farmer used to create it.
function writeAccount(tx, ref, invite) {
  const admin = invite.invitedBy || {};
  const { uid, fullName, email, barangay, rsbaNumber } = invite;
  tx.set(db.collection("users").doc(uid), {
    fullName,
    name: fullName,
    firstName: invite.firstName,
    lastName: invite.lastName,
    email,
    mobileNumber: invite.mobileNumber,
    role: "farmer",
    accountStatus: "active",
    // Approved by the office that added it, as in the Verification
    // Queue: approvalStatus, with isVerified mirroring it.
    approvalStatus: "approved",
    isVerified: true,
    verifiedAt: FieldValue.serverTimestamp(),
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: admin.uid || null,
    barangay,
    municipality: "Laurel",
    province: "Batangas",
    rsbaNumber,
    addedByAdmin: true,
    addedBy: admin.uid || null,
    confirmedByFarmerAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    // Agreed with the office, as registration records it in the app.
    termsAccepted: true,
    termsAcceptedAt: FieldValue.serverTimestamp(),
    termsAcceptedVia: "office",
    ...(invite.termsVersion ? { termsVersion: invite.termsVersion } : {}),
    ...(invite.privacyVersion ? { privacyVersion: invite.privacyVersion } : {}),
  });
  tx.set(db.collection("verificationDocs").doc(uid), {
    rsbaNumber,
    fullName,
    userId: uid,
    status: "approved",
    submittedAt: FieldValue.serverTimestamp(),
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: admin.uid || null,
    addedByAdmin: true,
  });
  tx.set(db.collection("audit_logs").doc(), {
    action: "CREATE_FARMER_ACCOUNT",
    details: `Added the farmer account of ${fullName} (${email}), ${barangay}, Laurel — confirmed by the farmer by email.`,
    device: invite.device || null,
    ip: invite.ip || null,
    location: invite.location || "Unknown",
    timestamp: FieldValue.serverTimestamp(),
    adminId: admin.uid || null,
    adminEmail: admin.email || null,
    adminName: admin.name || null,
    attemptedEmail: null,
  });
  tx.update(ref, { status: STATUS.confirmed, confirmedAt: FieldValue.serverTimestamp() });
}

exports.confirmFarmerAccount = onRequest(
  { region: REGION, memory: "256MiB", maxInstances: 5, secrets: MAIL_SECRETS },
  async (req, res) => {
    const nonce = crypto.randomBytes(16).toString("base64");
    res.set({
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": [
        "default-src 'none'",
        `style-src 'nonce-${nonce}' https://fonts.googleapis.com`,
        "font-src https://fonts.gstatic.com",
        "base-uri 'none'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ].join("; "),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    });

    // Opening the link only shows the question — mail scanners open links
    // too. The answer is the form's POST.
    const posting = req.method === "POST";
    if (!posting && req.method !== "GET" && req.method !== "HEAD") {
      res.set("Allow", "GET, HEAD, POST").status(405).send("Method Not Allowed");
      return;
    }
    const source = posting ? req.body || {} : req.query || {};
    const id = typeof source.id === "string" && /^[A-Za-z0-9]{1,40}$/.test(source.id) ? source.id : "";
    const token = typeof source.t === "string" ? source.t.slice(0, 100) : "";
    const ref = id ? invites().doc(id) : null;

    try {
      if (!posting) {
        const snap = ref ? await ref.get() : null;
        const invite = snap && snap.exists ? snap.data() : null;
        const state = inviteState(invite, token);
        if (state === STATUS.expired) await closeInvite(ref, STATUS.expired);
        if (state === STATUS.confirmed && invite.loginEnabled !== true) await enableLogin(ref, invite.uid);
        res.status(state === "invalid" ? 404 : 200).send(renderInvitePage(state, { invite, inviteId: id, token, nonce }));
        return;
      }

      const answer = source.answer === "decline" ? "decline" : "confirm";
      const outcome = !ref ? { state: "invalid" } : await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const invite = snap.exists ? snap.data() : null;
        const state = inviteState(invite, token);
        if (state !== STATUS.pending) return { state, invite };
        if (answer === "decline") {
          tx.update(ref, { status: STATUS.declined, closedAt: FieldValue.serverTimestamp() });
          return { state: STATUS.declined, invite, changed: true };
        }
        writeAccount(tx, ref, invite);
        return { state: STATUS.confirmed, invite, changed: true };
      });

      const { state, invite, changed } = outcome;
      if (state === STATUS.expired) await closeInvite(ref, STATUS.expired);
      if (changed && state === STATUS.declined) await releaseInviteLogin(invite.uid);
      if (changed && state === STATUS.confirmed) {
        await enableLogin(ref, invite.uid);
        // The account is ready, with a link to change the password the
        // office gave them (never the password itself).
        try {
          const link = resetPageLink(await getAuth().generatePasswordResetLink(invite.email));
          await sendMail(invite.email, templates.farmerAccountCreatedEmail({ name: invite.fullName, link }));
        } catch (err) {
          console.error(`confirmFarmerAccount(${invite.uid}) email failed:`, err.message);
        }
      }
      res.status(state === "invalid" ? 404 : 200).send(renderInvitePage(state, { invite, inviteId: id, token, nonce }));
    } catch (err) {
      console.error("confirmFarmerAccount failed:", err.message);
      res.status(503).send(renderInvitePage("error", { nonce }));
    }
  }
);

// Invites nobody answered: the login they hold would otherwise keep the
// email from registering in the app.
exports.expireFarmerInvites = onSchedule(
  { region: REGION, schedule: "every 6 hours", timeZone: "Asia/Manila" },
  async () => {
    const now = Date.now();
    const waiting = await invites().where("status", "==", STATUS.pending).get();
    for (const doc of waiting.docs) {
      const expiresAt = doc.data().expiresAt;
      if (expiresAt && expiresAt.toMillis() <= now) await closeInvite(doc.ref, STATUS.expired);
    }
  }
);
