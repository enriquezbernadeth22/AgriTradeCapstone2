/**
 * The farmer's own confirmation before an Admin-added account is created
 * (Admin Portal → User Accounts → Add Farmer; see admin_create_farmer.js).
 *
 * The Admin's details become an invite, farmerInvites/{inviteId}. The
 * farmer is emailed a link to the confirmation page (confirmFarmerAccount)
 * and the account is added only when they tap "Yes, it's me" there. The
 * link carries a random token; only its SHA-256 hash is stored, so the
 * invite document alone cannot confirm anything.
 *
 * No Firebase in here, so it can be unit tested
 * (see test/farmer_invite_logic.test.js).
 */

const crypto = require("crypto");

// How long the farmer has to confirm.
const INVITE_TTL_MS = 24 * 60 * 60 * 1000;

// The confirmation page: the confirmFarmerAccount function itself.
const CONFIRM_PAGE_URL =
  "https://asia-southeast1-agritrade-bef87.cloudfunctions.net/confirmFarmerAccount";

// pending → confirmed | declined | cancelled | expired
const STATUS = Object.freeze({
  pending: "pending",
  confirmed: "confirmed",
  declined: "declined",
  cancelled: "cancelled",
  expired: "expired",
});

function newInviteToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token)).digest("hex");
}

// Whether `token` is the one whose hash the invite keeps.
function tokenMatches(token, storedHash) {
  if (typeof token !== "string" || !token || typeof storedHash !== "string") return false;
  const given = Buffer.from(hashToken(token), "hex");
  const stored = Buffer.from(storedHash, "hex");
  return given.length === stored.length && crypto.timingSafeEqual(given, stored);
}

function confirmLink(inviteId, token, pageUrl = CONFIRM_PAGE_URL) {
  const url = new URL(pageUrl);
  url.searchParams.set("id", inviteId);
  url.searchParams.set("t", token);
  return url.toString();
}

function millis(value) {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  return null;
}

/**
 * What the page does with this invite and token:
 *
 *   "invalid"   no such invite, or the link's token is wrong
 *   "pending"   waiting for the farmer: the page asks "Is this you?"
 *   "expired"   still pending, but past its time
 *   otherwise   the invite's own final status
 */
function inviteState(invite, token, now = Date.now()) {
  if (!invite || !tokenMatches(token, invite.tokenHash)) return "invalid";
  const status = invite.status || STATUS.pending;
  if (status !== STATUS.pending) return status;
  const expiresAt = millis(invite.expiresAt);
  if (expiresAt != null && now >= expiresAt) return STATUS.expired;
  return STATUS.pending;
}

// "j***n@gmail.com": enough for the farmer to recognize, on a page anyone
// holding the link can open.
function maskEmail(email) {
  const text = String(email || "");
  const at = text.lastIndexOf("@");
  if (at < 1) return text;
  const name = text.slice(0, at);
  const shown = name.length <= 2 ? name[0] : `${name[0]}${"*".repeat(Math.min(name.length - 2, 6))}${name[name.length - 1]}`;
  return `${shown}${text.slice(at)}`;
}

// "+63 9•• ••• 4567"
function maskMobile(mobile) {
  const digits = String(mobile || "").replace(/\D/g, "");
  if (digits.length < 4) return "";
  return `+63 9•• ••• ${digits.slice(-4)}`;
}

// ---------------------------------------------------------------
// The confirmation page
// ---------------------------------------------------------------

function esc(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const MESSAGES = {
  invalid: {
    title: "Link not valid",
    body: "This confirmation link is not valid. Use the newest email from AgriTrade+, or contact the Agricultural Office of Laurel, Batangas.",
  },
  expired: {
    title: "This link has expired",
    body: "The time to confirm has passed, so no account was created. Ask the Agricultural Office of Laurel, Batangas to add you again.",
  },
  confirmed: {
    title: "Your account is ready",
    body: "Thank you for confirming. Your AgriTrade+ farmer account has been created, already approved for selling. Log in to the AgriTrade+ mobile app with this email address and the password the office gave you.",
  },
  declined: {
    title: "No account was created",
    body: "Thank you for letting us know. No AgriTrade+ account was created with your email address. If you think someone is using your details, please contact the Agricultural Office of Laurel, Batangas.",
  },
  cancelled: {
    title: "This request was cancelled",
    body: "The Agricultural Office cancelled this request, so no account was created. If you were expecting an account, please contact the office.",
  },
  error: {
    title: "Something went wrong",
    body: "Your answer could not be saved. Please open the link from your email again in a moment.",
  },
};

/**
 * The whole page, for `state` (see inviteState, plus "error"). A pending
 * invite shows its details and the two buttons, which post back to the
 * page with the invite id and token.
 */
function renderInvitePage(state, { invite = null, inviteId = "", token = "", nonce = "" } = {}) {
  const asking = state === STATUS.pending && invite;
  const message = MESSAGES[state] || MESSAGES.invalid;
  const title = asking ? "Is this you?" : message.title;

  const rows = asking
    ? [
      ["Name", invite.fullName],
      ["Email", maskEmail(invite.email)],
      ["Mobile", maskMobile(invite.mobileNumber)],
      ["Barangay", invite.barangay ? `${invite.barangay}, Laurel, Batangas` : ""],
    ].filter(([, value]) => value)
    : [];

  const body = asking
    ? `
      <p>The Agricultural Office of Laurel, Batangas is adding an AgriTrade+ farmer account for you with these details:</p>
      <table class="details">${rows.map(([label, value]) => `
        <tr><th>${esc(label)}</th><td>${esc(value)}</td></tr>`).join("")}
      </table>
      <p>The account is created only if you confirm.</p>
      <form method="post">
        <input type="hidden" name="id" value="${esc(inviteId)}">
        <input type="hidden" name="t" value="${esc(token)}">
        <button class="yes" type="submit" name="answer" value="confirm">Yes, it's me</button>
        <button class="no" type="submit" name="answer" value="decline">No, it's not me</button>
      </form>`
    : `<p>${esc(message.body)}</p>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>${esc(title)} — AgriTrade+</title>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700&display=swap">
  <style nonce="${esc(nonce)}">
    body { margin: 0; background: #EEF2EE; font-family: 'Montserrat', 'Segoe UI', Arial, sans-serif; color: #333; }
    .card { max-width: 480px; margin: 32px auto; background: #fff; border-radius: 14px; overflow: hidden; }
    .brand { background: #0E3210; color: #fff; font-size: 22px; font-weight: 700; padding: 20px 26px; }
    .content { padding: 24px 26px 28px; }
    h1 { font-size: 20px; margin: 0 0 14px; color: #0E3210; }
    p { font-size: 15px; line-height: 1.6; margin: 0 0 16px; }
    .details { width: 100%; border-collapse: collapse; background: #F4F7F4; border-radius: 10px; margin: 0 0 18px; }
    .details th { text-align: left; font-weight: 400; color: #666; padding: 8px 14px; font-size: 14px; white-space: nowrap; vertical-align: top; }
    .details td { font-weight: 600; color: #222; padding: 8px 14px 8px 0; font-size: 14px; }
    form { display: flex; flex-direction: column; gap: 10px; margin-top: 6px; }
    button { font: inherit; font-size: 15px; font-weight: 700; border-radius: 28px; padding: 13px 20px; cursor: pointer; }
    .yes { background: #0E3210; color: #fff; border: none; }
    .no { background: #fff; color: #9B2C2C; border: 1.5px solid #E2B4B4; }
    @media (max-width: 520px) { .card { margin: 0; border-radius: 0; min-height: 100vh; } }
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">AgriTrade+</div>
    <div class="content">
      <h1>${esc(title)}</h1>${body}
    </div>
  </div>
</body>
</html>`;
}

module.exports = {
  INVITE_TTL_MS,
  CONFIRM_PAGE_URL,
  STATUS,
  newInviteToken,
  hashToken,
  tokenMatches,
  confirmLink,
  inviteState,
  maskEmail,
  maskMobile,
  renderInvitePage,
};
