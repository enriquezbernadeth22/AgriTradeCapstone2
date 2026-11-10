// Run with: npm test   (from the functions folder)
// The admin-records import (import_admin_records_logic.js): what it
// refuses, how it maps the workbook to the app's own documents, and the
// cross-check of the workbook's summary sheets.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const L = require("../import_admin_records_logic");
const { parseSheet, readWorkbook } = require("../xlsx_reader");
const { outsideCoverage } = require("../delivery_coverage_logic");

const H = L.SHEETS;
const row = (sheet, values) => H[sheet].map((k) => (k in values ? values[k] : null));

// A small workbook with one of everything the real one has.
function fixture() {
  const s = {};
  const put = (sheet, rows) => (s[sheet] = [H[sheet], ...rows.map((r) => row(sheet, r))]);
  put("Locations", [
    { location_id: "LOC001", barangay: "San Gabriel", municipality: "Laurel", province: "Batangas", region: "CALABARZON", is_luzon: "Yes" },
    { location_id: "LOC002", barangay: "Poblacion", municipality: "Malvar", province: "Batangas", region: "CALABARZON", is_luzon: "Yes" },
  ]);
  const user = (id, role, loc, status = "Active") => ({
    user_id: id, role, display_name: `${role} ${id.slice(-1)} Dela Cruz`, email: `${id.toLowerCase()}@accounts.agritrade.example`,
    phone: "09000000001", location_id: loc, account_status: status, registered_at: "2026-08-01 08:00:00",
  });
  put("Users", [
    user("ADM0001", "Admin", null),
    user("BUY0001", "Buyer", "LOC002"),
    user("BUY0002", "Buyer", "LOC001", "Inactive"),
    user("FAR0001", "Farmer", "LOC001"),
    user("FAR0002", "Farmer", "LOC001", "Unverified"),
  ]);
  put("Farmer Verifications", [
    { farmer_id: "FAR0001", application_id: "VER0001", verification_status: "Approved", submitted_at: "2026-08-02 08:00:00",
      reviewed_at: "2026-08-03 08:00:00", reviewed_by: "ADM0001", rsbsa_no: "041011202600001", document_status: "Reviewed", location_id: "LOC001" },
    { farmer_id: "FAR0002", application_id: "VER0002", verification_status: "Pending", submitted_at: "2026-08-02 08:00:00",
      rsbsa_no: "041011202600002", document_status: "Submitted", location_id: "LOC001" },
  ]);
  const commodity = (id, name, category, unit, price) => ({
    commodity_id: id, product_name: name, category, unit, reference_price_php: price, reference_status: "Internal reference",
  });
  put("Commodities", [
    commodity("COM001", "Corn", "Grains", "kg", 62),
    commodity("COM019", "Chicken (Liveweight)", "Livestock", "kg", 230),
    commodity("COM023", "Coconut", "Others", "piece", 34),
  ]);
  const product = (id, com, name, category, unit, price, extra = {}) => ({
    product_id: id, farmer_id: "FAR0001", commodity_id: com, product_name: name, category, unit, price_php: price,
    wholesale_enabled: "No", listed_stock: 40, listing_status: "Active", posted_at: "2026-08-05 08:00:00",
    seller_location_id: "LOC001", delivery_supported: "Yes", pickup_supported: "Yes",
    delivery_coverage: "Selected Luzon areas only", ...extra,
  });
  put("Products", [
    product("PRD0001", "COM001", "Corn", "Grains", "kg", 60, { wholesale_enabled: "Yes" }),
    product("PRD0002", "COM019", "Chicken (Liveweight)", "Livestock", "kg", 220),
    product("PRD0003", "COM023", "Coconut", "Others", "piece", 30, { listing_status: "Archived" }),
  ]);
  const order = (id, buyer, prd, cat, unit, qty, price, status, dates, extra = {}) => ({
    order_id: id, buyer_id: buyer, farmer_id: "FAR0001", product_id: prd, category: cat, buyer_location_id: buyer === "BUY0001" ? "LOC002" : "LOC001",
    status, quantity: qty, unit, unit_price_php: price, total_php: Math.round(qty * price * 100) / 100, fulfilment: "Delivery",
    placed_at: "2026-09-01 08:00:00", ...dates, ...extra,
  });
  put("Orders", [
    order("ORD00001", "BUY0001", "PRD0001", "Grains", "kg", 3, 60, "Completed", { confirmed_at: "2026-09-01 10:00:00", shipped_at: "2026-09-02 08:00:00", completed_at: "2026-09-03 08:00:00" }),
    order("ORD00002", "BUY0001", "PRD0001", "Grains", "kg", 2, 60, "Cancelled", { confirmed_at: "2026-09-01 10:00:00", cancelled_at: "2026-09-02 08:00:00" }),
    order("ORD00003", "BUY0002", "PRD0002", "Livestock", "kg", 5, 220, "Confirmed", { confirmed_at: "2026-09-01 10:00:00" }, { fulfilment: "Pick-up" }),
    order("ORD00004", "BUY0002", "PRD0003", "Others", "piece", 10, 30, "Completed", { confirmed_at: "2026-09-01 10:00:00", completed_at: "2026-10-01 08:00:00" }),
  ]);
  put("Reviews", [
    { review_id: "REV0001", order_id: "ORD00001", buyer_id: "BUY0001", farmer_id: "FAR0001", product_id: "PRD0001", rating: 4, review_text: "Maayos.", reviewed_at: "2026-09-04 08:00:00" },
  ]);
  put("Reports", [
    { report_id: "RPT0001", reported_product_id: "PRD0001", reported_farmer_id: "FAR0001", reporter_buyer_id: "BUY0002", issue_type: "Price complaint",
      report_status: "Resolved", reported_at: "2026-09-05 08:00:00", assigned_admin_id: "ADM0001", resolution: "Warning / corrected listing" },
  ]);
  put("Violations", [
    { violation_id: "VIO0001", report_id: "RPT0001", farmer_id: "FAR0001", product_id: "PRD0001", violation_type: "Price complaint",
      action: "Written warning", action_at: "2026-09-06 08:00:00", admin_id: "ADM0001" },
  ]);
  put("Price History", [
    { price_record_id: "PHS00001", commodity_id: "COM019", commodity_name: "Chicken (Liveweight)", price_php: 228, unit: "kg", period: "2026-09",
      price_source: "Internal price reference", official_price: "No", recorded_at: "2026-09-01 08:00:00" },
  ]);
  put("Price Changes", [
    { change_id: "PCG0001", commodity_id: "COM001", old_price_php: 59, new_price_php: 63, change_reason: "Monthly price review", changed_by: "ADM0001", changed_at: "2026-09-19 07:32:29" },
  ]);
  put("Search Events", [
    { search_id: "SRC00001", buyer_id: "BUY0001", search_term: "Chicken (Liveweight)", category: "Others", buyer_location_id: "LOC002", searched_at: "2026-09-01 07:00:00" },
  ]);
  put("Conversations", [
    { conversation_id: "CONV0001", buyer_id: "BUY0001", farmer_id: "FAR0001", product_id: "PRD0001", started_at: "2026-08-20 08:00:00" },
    { conversation_id: "CONV0002", buyer_id: "BUY0001", farmer_id: "FAR0001", product_id: "PRD0002", started_at: "2026-08-25 08:00:00" },
  ]);
  put("Messages", [
    { message_id: "MSG00001", conversation_id: "CONV0001", sender_id: "BUY0001", message_type: "Text", body: "Available pa po?", sent_at: "2026-08-20 08:01:00" },
    { message_id: "MSG00002", conversation_id: "CONV0002", sender_id: "FAR0001", message_type: "Text", body: "Opo, meron pa.", sent_at: "2026-08-25 09:00:00" },
  ]);
  put("Notifications", [
    { notification_id: "NOT00001", user_id: "FAR0001", event_type: "Order received", related_order_id: "ORD00001", is_read: "Yes", created_at: "2026-09-01 08:00:05" },
  ]);
  put("Audit Logs", [
    { audit_id: "AUD00001", admin_id: "ADM0001", action: "Login", target_type: "System", target_id: null, at: "2026-09-01 07:00:00", ip_address: "192.0.2.10", result: "Success" },
  ]);
  s["KPI Summary"] = [["metric", "value", "definition"], ["Completed orders", 2, ""], ["Completed sales amount PHP", 480, ""], ["Unique buyers with completed orders", 2, ""]];
  s["Buyer Demand By Area"] = [["location_id", "location", "unique_completed_buyers", "completed_orders"], ["LOC002", "Poblacion, Malvar", 1, 1], ["LOC001", "San Gabriel, Laurel", 1, 1]];
  s["Product Demand By Category"] = [["category", "unique_buyers", "completed_orders"], ["Grains", 1, 1], ["Others", 1, 1]];
  s["Monthly Sales"] = [["month", "all_orders", "completed_orders", "completed_sales_php"], ["2026-09", 4, 1, 180], ["2026-10", 0, 1, 300]];
  return s;
}

// Sets one cell of [sheet]'s row whose id is [id].
function edit(s, sheet, id, column, value) {
  const header = s[sheet][0];
  const r = s[sheet].find((x) => x[0] === id);
  r[header.indexOf(column)] = value;
  return s;
}

const doc = (plan, p) => plan.find((d) => d.path === p)?.data;

test("dates are Philippine time; impossible dates are refused", () => {
  assert.strictEqual(L.manilaDate("2026-10-19 02:44:12").toISOString(), "2026-10-18T18:44:12.000Z");
  assert.strictEqual(L.manilaDate("2026-10").toISOString(), "2026-09-30T16:00:00.000Z");
  assert.strictEqual(L.manilaMonth(L.manilaDate("2026-11-01 00:30:00")), "2026-11");
  assert.strictEqual(L.manilaDate("2026-02-31 08:00:00"), null);
  assert.strictEqual(L.manilaDate("10/19/2026"), null);
});

test("names split into first and last, particles kept with the last", () => {
  assert.deepStrictEqual(L.splitName("Juan Dela Cruz"), { firstName: "Juan", lastName: "Dela Cruz" });
  assert.deepStrictEqual(L.splitName("Maria Clara Santos"), { firstName: "Maria Clara", lastName: "Santos" });
  assert.deepStrictEqual(L.splitName("Celine"), { firstName: "Celine", lastName: "" });
});

test("blank rows are skipped and text is trimmed", () => {
  const rows = L.sheetRecords([["a", "b"], [" x ", 1], [null, null], ["", "  "]]);
  assert.deepStrictEqual(rows.map((r) => [r.a, r.b]), [["x", 1]]);
});

test("a consistent workbook passes", () => {
  const { errors } = L.validateWorkbook(fixture());
  assert.deepStrictEqual(errors, []);
});

test("refused: what would put wrong or invented records in", () => {
  const cases = [
    [(s) => edit(s, "Farmer Verifications", "FAR0001", "rsbsa_no", 41011202600001), /leading zeros are lost/],
    [(s) => edit(s, "Farmer Verifications", "FAR0002", "rsbsa_no", "041011202600001"), /also used by FAR0001/],
    [(s) => edit(s, "Commodities", "COM001", "product_name", "Duck"), /use Cattle instead/],
    [(s) => edit(s, "Orders", "ORD00001", "total_php", 999), /not quantity × unit price/],
    [(s) => edit(s, "Orders", "ORD00001", "product_id", "PRD9999"), /not in Products/],
    [(s) => edit(s, "Orders", "ORD00003", "completed_at", "2026-09-05 08:00:00"), /completed_at is set on a Confirmed order/],
    [(s) => edit(s, "Orders", "ORD00001", "completed_at", "2026-08-01 08:00:00"), /before the step before it/],
    [(s) => edit(s, "Reviews", "REV0001", "order_id", "ORD00003"), /only completed orders are reviewed/],
    [(s) => edit(s, "Price History", "PHS00001", "official_price", "Yes"), /government-certified/],
    [(s) => edit(s, "Notifications", "NOT00001", "user_id", "ADM0001"), /admin accounts are not imported/],
    [(s) => edit(s, "Users", "BUY0001", "phone", 9000000001), /leading 0 is lost/],
    [(s) => edit(s, "Products", "PRD0001", "farmer_id", "FAR0002"), /not an approved farmer/],
    [(s) => edit(s, "Locations", "LOC002", "is_luzon", "No"), /Luzon only/],
    [(s) => edit(s, "Messages", "MSG00001", "sender_id", "BUY0002"), /not in conversation/],
  ];
  for (const [change, message] of cases) {
    const { errors } = L.validateWorkbook(change(fixture()));
    assert.ok(errors.some((e) => message.test(e)), `expected ${message} in ${JSON.stringify(errors)}`);
  }
  const missing = fixture();
  missing.Orders[0] = missing.Orders[0].filter((h) => h !== "total_php");
  assert.ok(L.validateWorkbook(missing).errors.some((e) => /column "total_php" is missing/.test(e)));
});

test("the plan: the app's own collections, ids and fields", () => {
  const plan = L.buildPlan(fixture());
  // Every document is marked and every path is written once.
  assert.ok(plan.every((d) => d.data.importBatch === L.BATCH_ID && d.data.importSourceId));
  assert.strictEqual(new Set(plan.map((d) => d.path)).size, plan.length);
  // Admins are never created by the import.
  assert.ok(!plan.some((d) => d.path === "users/ADM0001"));
  assert.strictEqual(doc(plan, "verificationDocs/FAR0001").reviewedByName, "Admin 1 Dela Cruz");

  const buyer = doc(plan, "users/BUY0002");
  assert.strictEqual(buyer.role, "buyer");
  assert.strictEqual(buyer.accountStatus, "active"); // Inactive is not an app state.
  assert.strictEqual(buyer.lastName, "Dela Cruz");
  const pending = doc(plan, "users/FAR0002");
  assert.strictEqual(pending.approvalStatus, "pending");
  assert.strictEqual(pending.isVerified, false);
  assert.strictEqual(pending.rsbaNumber, "041011202600002");
  assert.strictEqual(doc(plan, "users/FAR0001").rating, 4);

  // Chicken (Liveweight) is the app's Chicken, per kg; Others is Fruits.
  const chicken = doc(plan, "products/PRD0002");
  assert.strictEqual(chicken.name, "Chicken");
  assert.strictEqual(chicken.unit, "kg");
  assert.strictEqual(chicken.sellingOption, "live");
  assert.strictEqual(doc(plan, "market_prices/chicken").unit, "kg");
  assert.strictEqual(doc(plan, "market_prices/chicken/history/PHS00001").price, 228);
  assert.strictEqual(doc(plan, "market_prices/corn/history/PCG0001").previousPrice, 59);
  assert.match(doc(plan, "market_prices/corn").source, /not DA-issued/);
  assert.strictEqual(doc(plan, "products/PRD0003").category, "Fruits");
  assert.strictEqual(doc(plan, "products/PRD0003").isArchived, true);
  assert.strictEqual(doc(plan, "orders/ORD00004").category, "Fruits");
  // No wholesale price is made up.
  assert.strictEqual(doc(plan, "products/PRD0001").wholesaleEnabled, false);
  assert.strictEqual(doc(plan, "products/PRD0001").completedOrderCount, 1);

  // Stock was taken on confirming; a cancelled order gave it back.
  assert.ok(doc(plan, "orders/ORD00003").stockDeductedAt instanceof Date);
  assert.strictEqual(doc(plan, "orders/ORD00002").stockDeductedAt, undefined);
  assert.strictEqual(doc(plan, "orders/ORD00002").status, "cancelled");
  assert.strictEqual(doc(plan, "orders/ORD00001").reviewRating, 4);
  assert.strictEqual(doc(plan, "orders/ORD00003").deliveryMethod, "pickup");
  assert.strictEqual(doc(plan, "orders/ORD00003").quantityLabel, "5 kg");
  assert.strictEqual(doc(plan, "productReviews/ORD00001").sellerId, "FAR0001");
  assert.strictEqual(doc(plan, "violations/RPT0001").actionTaken, "warning");
  assert.strictEqual(doc(plan, "reports/RPT0001").status, "resolved");
});

test("no imported delivery order is outside its listing's coverage", () => {
  const plan = L.buildPlan(fixture());
  for (const o of plan.filter((d) => /^orders\//.test(d.path))) {
    const product = doc(plan, `products/${o.data.productId}`);
    assert.strictEqual(outsideCoverage(o.data, product), false, o.path);
  }
});

test("chats: one thread per buyer and farmer, under the app's id", () => {
  const plan = L.buildPlan(fixture());
  const threads = plan.filter((d) => /^conversations\/[^/]+$/.test(d.path));
  assert.deepStrictEqual(threads.map((d) => d.path), ["conversations/BUY0001_FAR0001"]);
  assert.deepStrictEqual(threads[0].data.importSourceIds, ["CONV0001", "CONV0002"]);
  assert.strictEqual(threads[0].data.lastMessage, "Opo, meron pa.");
  assert.strictEqual(plan.filter((d) => d.path.startsWith("conversations/BUY0001_FAR0001/messages/")).length, 2);
});

test("searches never feed Trending Searches; audit logs only when asked", () => {
  const plan = L.buildPlan(fixture());
  const search = doc(plan, "searchEvents/SRC00001");
  assert.strictEqual(search.userId, undefined);
  assert.strictEqual(search.query, "chicken (liveweight)");
  assert.ok(!plan.some((d) => d.path.startsWith("audit_logs/")));
  const withLogs = L.buildPlan(fixture(), { includeAuditLogs: true });
  assert.strictEqual(doc(withLogs, "audit_logs/AUD00001").action, "LOGIN_SUCCESS");
});

test("the summary sheets are checked against the documents", () => {
  const s = fixture();
  const checks = L.crossCheck(s, L.summarize(L.buildPlan(s)), { notImported: ["auditLogs"] });
  assert.deepStrictEqual(checks.filter((c) => c.ok === false), []);
  assert.ok(checks.some((c) => c.check === "Product Demand · Others (→ Fruits) · unique buyers" && c.ok));
  // A summary that does not add up is shown as not matching.
  s["KPI Summary"][2][1] = 999;
  const wrong = L.crossCheck(s, L.summarize(L.buildPlan(s)));
  assert.ok(wrong.some((c) => c.check === "KPI · Completed sales amount PHP" && c.ok === false));
});

test("the xlsx reader reads shared, inline and number cells", () => {
  const xml =
    '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>R&amp;D</t></is></c></row>' +
    '<row r="2"><c r="A2"><v>12.5</v></c><c r="B2" t="b"><v>1</v></c><c r="C2" t="str"><v>041011202600001</v></c></row></sheetData></worksheet>';
  assert.deepStrictEqual(parseSheet(xml, ["order_id"]), [
    ["order_id", null, "R&D"],
    [12.5, true, "041011202600001"],
  ]);
});

const workbook = "C:/Users/Daniella/Downloads/AgriTrade_Admin_Records_Aug-Nov_2026.xlsx";
test("the real workbook, when on this PC, passes and matches its summaries", { skip: !fs.existsSync(workbook) }, () => {
  const s = readWorkbook(workbook);
  assert.deepStrictEqual(L.validateWorkbook(s).errors, []);
  const checks = L.crossCheck(s, L.summarize(L.buildPlan(s)), { notImported: ["auditLogs"] });
  // Only the Monthly Sales sheet's repeated rows disagree with its Orders.
  assert.ok(checks.filter((c) => c.ok === false).every((c) => /repeated row/.test(c.check)));
});

test("a commodity's photo, when given, is on its listings, orders and chats", () => {
  const url = "https://firebasestorage.googleapis.com/v0/b/x/o/corn.jpg?alt=media&token=t";
  const plan = L.buildPlan(fixture(), { photoUrls: { corn: url } });
  assert.deepStrictEqual(doc(plan, "products/PRD0001").imageUrls, [url]);
  assert.strictEqual(doc(plan, "orders/ORD00001").imageUrl, url);
  // No photo for the others: nothing is made up.
  assert.deepStrictEqual(doc(plan, "products/PRD0002").imageUrls, []);
  assert.strictEqual(doc(plan, "products/PRD0002").imageUrl, "");
});
