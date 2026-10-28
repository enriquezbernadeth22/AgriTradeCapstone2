// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const logic = require("../farmer_invite_logic");
const templates = require("../email_templates");

const token = logic.newInviteToken();
const invite = (fields = {}) => ({
  status: "pending",
  tokenHash: logic.hashToken(token),
  fullName: "Juan Dela Cruz",
  email: "juan.delacruz@gmail.com",
  mobileNumber: "+639171234567",
  barangay: "Gulod",
  expiresAt: Date.now() + 60_000,
  ...fields,
});

test("only the hash of the link's token is kept, and only it matches", () => {
  const hash = logic.hashToken(token);
  assert.notStrictEqual(hash, token);
  assert.ok(logic.tokenMatches(token, hash));
  assert.ok(!logic.tokenMatches(logic.newInviteToken(), hash));
  assert.ok(!logic.tokenMatches("", hash));
  assert.ok(!logic.tokenMatches(undefined, hash));
  assert.ok(!logic.tokenMatches(token, undefined));
});

test("the state of an invite, for the link that opened it", () => {
  assert.strictEqual(logic.inviteState(invite(), token), "pending");
  assert.strictEqual(logic.inviteState(invite(), "wrong"), "invalid");
  assert.strictEqual(logic.inviteState(null, token), "invalid");
  assert.strictEqual(logic.inviteState(invite({ expiresAt: Date.now() - 1 }), token), "expired");
  assert.strictEqual(logic.inviteState(invite({ status: "confirmed", expiresAt: 0 }), token), "confirmed");
  assert.strictEqual(logic.inviteState(invite({ status: "declined" }), token), "declined");
  assert.strictEqual(logic.inviteState(invite({ status: "cancelled" }), token), "cancelled");
  // A wrong token says nothing about the invite, whatever its status.
  assert.strictEqual(logic.inviteState(invite({ status: "confirmed" }), "wrong"), "invalid");
  // Firestore Timestamps too.
  const at = { toMillis: () => Date.now() - 1 };
  assert.strictEqual(logic.inviteState(invite({ expiresAt: at }), token), "expired");
});

test("the link points at the confirmation page with the invite and token", () => {
  const link = new URL(logic.confirmLink("abc123", token));
  assert.strictEqual(`${link.origin}${link.pathname}`, logic.CONFIRM_PAGE_URL);
  assert.strictEqual(link.searchParams.get("id"), "abc123");
  assert.strictEqual(link.searchParams.get("t"), token);
});

test("the page shows the email and mobile only partly", () => {
  assert.strictEqual(logic.maskEmail("juan.delacruz@gmail.com"), "j******z@gmail.com");
  assert.strictEqual(logic.maskEmail("jo@x.ph"), "j@x.ph");
  assert.strictEqual(logic.maskMobile("+639171234567"), "+63 9•• ••• 4567");
});

test("a pending invite asks \"Is this you?\" with both answers", () => {
  const html = logic.renderInvitePage("pending", { invite: invite(), inviteId: "abc123", token, nonce: "n0" });
  assert.match(html, /Is this you\?/);
  assert.match(html, /Juan Dela Cruz/);
  assert.match(html, /Gulod, Laurel, Batangas/);
  assert.match(html, /value="confirm">Yes, it's me</);
  assert.match(html, /value="decline">No, it's not me</);
  assert.match(html, /<form method="post">/);
  assert.match(html, /<style nonce="n0">/);
  // Not the full email or mobile number.
  assert.ok(!html.includes("juan.delacruz@gmail.com"));
  assert.ok(!html.includes("9171234567"));
});

test("every other state is a message, with no form", () => {
  for (const [state, text] of [
    ["confirmed", "Your account is ready"],
    ["declined", "No account was created"],
    ["expired", "This link has expired"],
    ["cancelled", "This request was cancelled"],
    ["invalid", "Link not valid"],
    ["error", "Something went wrong"],
  ]) {
    const html = logic.renderInvitePage(state, { invite: invite(), inviteId: "abc123", token });
    assert.ok(html.includes(text), state);
    assert.ok(!html.includes("<form"), state);
  }
});

test("names on the page are escaped", () => {
  const html = logic.renderInvitePage("pending", { invite: invite({ fullName: "<b>Juan</b>" }), inviteId: "a", token });
  assert.ok(!html.includes("<b>Juan</b>"));
  assert.ok(html.includes("&lt;b&gt;Juan&lt;/b&gt;"));
});

test("the confirmation email has the details and the \"Yes, it's me\" button", () => {
  const link = logic.confirmLink("abc123", token);
  const mail = templates.farmerConfirmAccountEmail({
    name: "Juan Dela Cruz",
    link,
    details: [["Name", "Juan Dela Cruz"], ["Barangay", "Gulod, Laurel, Batangas"]],
  });
  assert.strictEqual(mail.subject, "Confirm your AgriTrade+ farmer account");
  assert.ok(mail.text.includes(link));
  assert.ok(mail.text.includes("Barangay: Gulod, Laurel, Batangas"));
  assert.ok(mail.html.includes("Yes, it&#39;s me"));
  assert.ok(mail.html.includes(`href="${link.replace(/&/g, "&amp;")}"`));
  assert.ok(!/password/i.test(mail.text));
});
