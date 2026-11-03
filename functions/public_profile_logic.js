// What of users/{uid} other signed-in users may see, as publicProfiles/{uid}:
// the name, photo, general area, role and kind of buyer or farmer, ratings,
// and the month the account was made. Never the email, phone number, exact
// location or anything about moderation. Used by syncPublicProfile
// (index.js) and backfill_public_profiles.js, so the two never differ.

const TEXT_FIELDS = [
  "role", "name", "fullName", "photoUrl", "barangay", "municipality", "province",
  "approvalStatus",
  // "What best describes you" (lib/data/account_types.dart), shown on the
  // buyer's profile a farmer opens from a chat.
  "buyerType", "farmerType",
];
const NUMBER_FIELDS = ["rating", "reviewCount"];

/** The public projection of one users/{uid} document. */
function publicProfileOf(data) {
  const profile = {};
  for (const key of TEXT_FIELDS) {
    const value = data[key];
    // Photo URLs (Google account photos especially) can run well past 200.
    const maxLength = key === "photoUrl" ? 2000 : 200;
    if (typeof value === "string" && value.length <= maxLength) profile[key] = value;
  }
  for (const key of NUMBER_FIELDS) {
    const value = data[key];
    if (typeof value === "number" && Number.isFinite(value)) profile[key] = value;
  }
  // When the account was made ("Member since"): kept as the same Firestore
  // timestamp, nothing finer is added.
  const created = data.createdAt;
  if (created && typeof created.toMillis === "function") profile.memberSince = created;
  return profile;
}

module.exports = { publicProfileOf };
