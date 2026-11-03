// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { checkFarmerDetails, passwordChangedSince } = require("../admin_create_farmer_logic");

test("a password change is seen by the time Firebase moved its tokens to", () => {
  const since = Date.parse("2026-11-02T10:00:00Z");
  assert.strictEqual(passwordChangedSince("Mon, 02 Nov 2026 10:05:00 GMT", since), true);
  assert.strictEqual(passwordChangedSince("Mon, 02 Nov 2026 09:59:00 GMT", since), false);
  // Nothing to compare: it is taken as not changed, so the farmer is still asked.
  assert.strictEqual(passwordChangedSince(undefined, since), false);
  assert.strictEqual(passwordChangedSince("Mon, 02 Nov 2026 10:05:00 GMT", undefined), false);
});

const valid = {
  firstName: "  Juan ",
  lastName: " Dela   Cruz ",
  email: " Juan.DelaCruz@Gmail.com ",
  mobileNumber: "0912 345 6789",
  barangay: "san gabriel",
  farmerType: "Crop Farmer",
  rsbaNumber: " 0410140010000ab ",
  password: "Laurel-Farm2026",
  termsAccepted: true,
  termsVersion: "tos-draft-1",
  privacyVersion: "privacy-draft-1",
};

test("valid details are cleaned the way the app stores them", () => {
  assert.deepStrictEqual(checkFarmerDetails(valid), {
    firstName: "Juan",
    lastName: "Dela Cruz",
    fullName: "Juan Dela Cruz",
    email: "juan.delacruz@gmail.com",
    mobileNumber: "+639123456789",
    barangay: "San Gabriel",
    farmerType: "Crop Farmer",
    rsbaNumber: "0410140010000AB",
    password: "Laurel-Farm2026",
    termsVersion: "tos-draft-1",
    privacyVersion: "privacy-draft-1",
  });
});

test("every mobile number spelling becomes +639XXXXXXXXX", () => {
  for (const mobileNumber of ["09123456789", "+639123456789", "639123456789", "9123456789"]) {
    assert.strictEqual(
      checkFarmerDetails({ ...valid, mobileNumber }).mobileNumber,
      "+639123456789",
    );
  }
});

test("each wrong detail is named", () => {
  assert.match(checkFarmerDetails({ ...valid, firstName: "" }).error, /first name/);
  assert.match(checkFarmerDetails({ ...valid, lastName: "Cruz2" }).error, /last name cannot contain numbers/);
  assert.match(checkFarmerDetails({ ...valid, lastName: "C" }).error, /last name/);
  assert.match(checkFarmerDetails({ ...valid, email: "juan@" }).error, /email/);
  assert.match(checkFarmerDetails({ ...valid, mobileNumber: "0812345678" }).error, /mobile/);
  assert.match(checkFarmerDetails({ ...valid, barangay: "Makati" }).error, /barangay/);
  assert.match(checkFarmerDetails({ ...valid, rsbaNumber: "12345" }).error, /RSBSA/);
  assert.match(checkFarmerDetails(null).error, /first name/);
});

test("the password follows the app's password rules", () => {
  assert.match(checkFarmerDetails({ ...valid, password: "Short1!" }).error, /^The password needs at least 12/);
  assert.match(checkFarmerDetails({ ...valid, password: "laurel-farm2026" }).error, /uppercase/);
  assert.match(checkFarmerDetails({ ...valid, password: "LaurelFarm2026" }).error, /symbol/);
  assert.match(checkFarmerDetails({ ...valid, password: undefined }).error, /password/);
});

test("the farmer's agreement to the Terms is required", () => {
  assert.match(checkFarmerDetails({ ...valid, termsAccepted: false }).error, /Terms of Service/);
  assert.match(checkFarmerDetails({ ...valid, termsAccepted: "yes" }).error, /Terms of Service/);
});

test("Add Farmer needs one of the farmer types", () => {
  assert.strictEqual(checkFarmerDetails(valid).farmerType, "Crop Farmer");
  assert.match(checkFarmerDetails({ ...valid, farmerType: "" }).error, /best describes/);
  assert.match(checkFarmerDetails({ ...valid, farmerType: "Fisher" }).error, /best describes/);
});
