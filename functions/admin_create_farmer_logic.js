/**
 * Checks the details an Admin enters to add a farmer account from the
 * Admin Portal (User Accounts → Add Farmer; see admin_create_farmer.js).
 * The same rules as the app's own registration form, so an account the
 * Admin adds looks exactly like one a farmer registered. No Firebase in
 * here, so it can be unit tested (see test/admin_create_farmer_logic.test.js).
 */

// lib/data/laurel_barangays.dart — farmers are registered in Laurel only.
const LAUREL_BARANGAYS = [
  "As-Is", "Balakilong", "Barangay 1", "Barangay 2", "Barangay 3",
  "Barangay 4", "Barangay 5", "Berinayan", "Bugaan East", "Bugaan West",
  "Buso-buso", "Dayap Itaas", "Gulod", "J. Leviste", "Molinete",
  "Niyugan", "Paliparan", "San Gabriel", "San Gregorio", "Santa Maria", "Ticub",
];

// lib/services/rsba_number.dart
const RSBSA_MIN = 15;
const RSBSA_MAX = 17;

const { passwordProblem } = require("./password_policy");

/**
 * The cleaned details, or `{ error }` naming the first one that is wrong.
 *
 *  - firstName, lastName: 2–40 characters each, no digits; joined into
 *    fullName
 *  - email: a valid address, stored in lower case
 *  - mobileNumber: a Philippine mobile number ("09…", "+639…" or the 10
 *    digits after +63), stored as "+639XXXXXXXXX"
 *  - barangay: one of Laurel's barangays
 *  - rsbaNumber: the farmer's RSBSA number (15–17 letters or digits),
 *    stored in capitals
 *  - password: set by the Admin, by the app's password rules
 *    (password_policy.js); never stored by AgriTrade+ itself
 *  - termsAccepted: true — the farmer agreed to the Terms of Service and
 *    Privacy Policy with the office (termsVersion / privacyVersion say
 *    which texts)
 */
function checkFarmerDetails(input) {
  const data = input || {};
  const text = (value) => (typeof value === "string" ? value.trim() : "");

  // First name and Last name, as registration asks for them; joined into
  // the full name every screen shows (lib/services/person_name.dart).
  const namePart = (value, label) => {
    const name = text(value).replace(/\s+/g, " ");
    if (!name) return { error: `Enter the farmer's ${label}.` };
    if (/[0-9]/.test(name)) return { error: `The ${label} cannot contain numbers.` };
    if (name.length < 2 || name.length > 40) {
      return { error: `The ${label} must be 2–40 characters.` };
    }
    return { name };
  };
  const first = namePart(data.firstName, "first name");
  if (first.error) return { error: first.error };
  const last = namePart(data.lastName, "last name");
  if (last.error) return { error: last.error };
  const firstName = first.name;
  const lastName = last.name;
  const fullName = `${firstName} ${lastName}`;

  const email = text(data.email).toLowerCase();
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { error: "Enter a valid email address." };
  }

  const digits = text(data.mobileNumber).replace(/[\s()-]/g, "");
  const local = digits.startsWith("+63")
    ? digits.slice(3)
    : digits.startsWith("63") && digits.length === 12
      ? digits.slice(2)
      : digits.startsWith("0")
        ? digits.slice(1)
        : digits;
  if (!/^9\d{9}$/.test(local)) {
    return { error: "Enter a valid Philippine mobile number (09XX XXX XXXX)." };
  }
  const mobileNumber = `+63${local}`;

  const barangay = LAUREL_BARANGAYS.find(
    (name) => name.toLowerCase() === text(data.barangay).toLowerCase(),
  );
  if (!barangay) {
    return { error: "Choose the farmer's barangay in Laurel." };
  }

  const rsbaNumber = text(data.rsbaNumber).toUpperCase();
  if (rsbaNumber.length < RSBSA_MIN || rsbaNumber.length > RSBSA_MAX ||
      !/^[A-Z0-9]+$/.test(rsbaNumber)) {
    return {
      error: `Enter the farmer's RSBSA number (${RSBSA_MIN}–${RSBSA_MAX} letters or digits).`,
    };
  }

  const password = typeof data.password === "string" ? data.password : "";
  const problem = passwordProblem(password);
  if (problem) return { error: problem.replace("The new password", "The password") };

  if (data.termsAccepted !== true) {
    return {
      error: "Confirm that the farmer agreed to the Terms of Service and Privacy Policy.",
    };
  }
  const version = (value) => text(value).slice(0, 40) || null;

  return {
    firstName,
    lastName,
    fullName,
    email,
    mobileNumber,
    barangay,
    rsbaNumber,
    password,
    termsVersion: version(data.termsVersion),
    privacyVersion: version(data.privacyVersion),
  };
}

module.exports = { LAUREL_BARANGAYS, checkFarmerDetails };
