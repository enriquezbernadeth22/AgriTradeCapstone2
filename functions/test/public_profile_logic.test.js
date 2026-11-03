// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { publicProfileOf } = require("../public_profile_logic");

const created = { toMillis: () => 1730000000000 };

test("a buyer's public profile: name, photo, area, kind of buyer, member since", () => {
  const profile = publicProfileOf({
    role: "buyer", name: "Junior Pesigan", photoUrl: "https://x/p.jpg",
    barangay: "Poblacion", municipality: "Malvar", province: "Batangas",
    buyerType: "Market Vendor", createdAt: created,
  });
  assert.deepStrictEqual(profile, {
    role: "buyer", name: "Junior Pesigan", photoUrl: "https://x/p.jpg",
    barangay: "Poblacion", municipality: "Malvar", province: "Batangas",
    buyerType: "Market Vendor", memberSince: created,
  });
});

test("never the email, phone, exact location or moderation details", () => {
  const profile = publicProfileOf({
    name: "Ana", email: "ana@x.com", phone: "09171234567", latitude: 14.1,
    longitude: 121.1, accountStatus: "suspended", suspensionReason: "spam",
    recoveryEmail: "a@y.com",
  });
  assert.deepStrictEqual(profile, { name: "Ana" });
});

test("ratings are kept as numbers; odd values are left out", () => {
  assert.deepStrictEqual(publicProfileOf({ rating: 4.5, reviewCount: 3 }), { rating: 4.5, reviewCount: 3 });
  assert.deepStrictEqual(publicProfileOf({ rating: "5", reviewCount: NaN, createdAt: "2026" }), {});
});

test("a long photo link is kept, a long name is not", () => {
  const long = "x".repeat(500);
  assert.strictEqual(publicProfileOf({ photoUrl: long }).photoUrl, long);
  assert.strictEqual(publicProfileOf({ name: long }).name, undefined);
});
