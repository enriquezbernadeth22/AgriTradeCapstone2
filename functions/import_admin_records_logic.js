/**
 * The pure part of the admin-records import (import_admin_records.js):
 * reads the sheets of AgriTrade_Admin_Records_Aug-Nov_2026.xlsx, checks
 * them, and turns them into the Firestore documents the app itself writes
 * (the same collections, ids and field names as AuthService, ProductService,
 * OrderService, ReviewService, the Moderation Queue and Price Management),
 * plus the cross-check of the workbook's own summary sheets against numbers
 * computed from those documents.
 *
 * No Firebase here, so it is tested on its own (test/import_admin_records.test.js).
 *
 * Every document carries `importBatch` (and `importSourceId`, the
 * workbook's own id), so the import can be checked, repeated without
 * duplicates and removed again without touching anything else.
 */

const BATCH_ID = "admin-records-aug-nov-2026";

// The workbook's categories that the app names differently. Coconut and
// Banana are under "Others" in the workbook and under Fruits in the app's
// own commodity list (commodity_master_list.dart).
const CATEGORY_RENAMES = { Others: "Fruits" };
const APP_CATEGORIES = ["Grains", "Root Crops", "Vegetables", "Spices", "Fruits", "Livestock"];

// Workbook commodity names that are one of the app's own under another
// name: "Chicken (Liveweight)" is the app's Chicken. Its unit stays the
// workbook's "kg", the unit Price Management already has for Chicken in
// the project, so its listings and reference prices share one unit.
const COMMODITY_RENAMES = {
  "Chicken (Liveweight)": { name: "Chicken" },
};

// Never sold on AgriTrade+: the brief says Cattle instead of Duck.
const REFUSED_COMMODITIES = { duck: "Duck is not an AgriTrade+ commodity; use Cattle instead." };

// Units counted in whole items: plural when not 1 (formatStock).
const COUNT_UNITS = new Set(["head", "piece", "bundle", "tray", "sack"]);

// The required columns of each sheet the import reads.
const SHEETS = {
  Locations: ["location_id", "barangay", "municipality", "province", "region", "is_luzon"],
  Users: ["user_id", "role", "display_name", "email", "phone", "location_id", "account_status", "registered_at"],
  "Farmer Verifications": [
    "farmer_id", "application_id", "verification_status", "submitted_at", "reviewed_at",
    "reviewed_by", "rsbsa_no", "document_status", "location_id",
  ],
  Commodities: ["commodity_id", "product_name", "category", "unit", "reference_price_php", "reference_status"],
  Products: [
    "product_id", "farmer_id", "commodity_id", "product_name", "category", "unit", "price_php",
    "wholesale_enabled", "listed_stock", "listing_status", "posted_at", "seller_location_id",
    "delivery_supported", "pickup_supported", "delivery_coverage",
  ],
  Orders: [
    "order_id", "buyer_id", "farmer_id", "product_id", "category", "buyer_location_id", "status",
    "quantity", "unit", "unit_price_php", "total_php", "fulfilment", "placed_at", "confirmed_at",
    "shipped_at", "completed_at", "cancelled_at",
  ],
  Reviews: ["review_id", "order_id", "buyer_id", "farmer_id", "product_id", "rating", "review_text", "reviewed_at"],
  Reports: [
    "report_id", "reported_product_id", "reported_farmer_id", "reporter_buyer_id", "issue_type",
    "report_status", "reported_at", "assigned_admin_id", "resolution",
  ],
  Violations: ["violation_id", "report_id", "farmer_id", "product_id", "violation_type", "action", "action_at", "admin_id"],
  "Price History": [
    "price_record_id", "commodity_id", "commodity_name", "price_php", "unit", "period",
    "price_source", "official_price", "recorded_at",
  ],
  "Price Changes": ["change_id", "commodity_id", "old_price_php", "new_price_php", "change_reason", "changed_by", "changed_at"],
  "Search Events": ["search_id", "buyer_id", "search_term", "category", "buyer_location_id", "searched_at"],
  Conversations: ["conversation_id", "buyer_id", "farmer_id", "product_id", "started_at"],
  Messages: ["message_id", "conversation_id", "sender_id", "message_type", "body", "sent_at"],
  Notifications: ["notification_id", "user_id", "event_type", "related_order_id", "is_read", "created_at"],
  "Audit Logs": ["audit_id", "admin_id", "action", "target_type", "target_id", "at", "ip_address", "result"],
};

// The id column of each sheet.
const ID_COLUMN = {
  Locations: "location_id",
  Users: "user_id",
  "Farmer Verifications": "farmer_id",
  Commodities: "commodity_id",
  Products: "product_id",
  Orders: "order_id",
  Reviews: "review_id",
  Reports: "report_id",
  Violations: "violation_id",
  "Price History": "price_record_id",
  "Price Changes": "change_id",
  "Search Events": "search_id",
  Conversations: "conversation_id",
  Messages: "message_id",
  Notifications: "notification_id",
  "Audit Logs": "audit_id",
};

const ORDER_STATUSES = {
  Pending: "pending",
  Confirmed: "confirmed",
  Shipped: "shipped",
  Completed: "completed",
  Cancelled: "cancelled",
  Rejected: "rejected",
};
const VERIFICATION_STATUSES = { Approved: "approved", Pending: "pending", Rejected: "rejected" };
const REPORT_STATUSES = { Pending: "pending", "Under Review": "under_review", Resolved: "resolved" };
// The app has no "inactive" or "unverified" account state: an account is
// active, suspended or banned (Moderation Queue). An inactive buyer is
// still an active account; an unverified farmer's state is their
// application's (pending or rejected).
const ACCOUNT_STATUSES = {
  Active: "active",
  Inactive: "active",
  Unverified: "active",
  Suspended: "suspended",
  Banned: "banned",
};
// The Moderation Queue's actions (ViolationAction in moderation_model.dart).
const VIOLATION_ACTIONS = {
  "Written warning": { code: "warning", severity: "warning" },
  "Listing suspended": { code: "hidden", severity: "listing" },
  "Listing corrected": { code: "violation_recorded", severity: "record" },
  "Restricted posting": { code: "violation_recorded", severity: "record" },
};
const NOTIFICATION_TYPES = {
  "Order status updated": { type: "order_status", category: "orders", title: "Order status updated" },
  "Order received": { type: "new_order", category: "orders", title: "New order received" },
  "New message": { type: "chat_message", category: "messages", title: "New message" },
  "Product review": { type: "review", category: "reviews", title: "New product review" },
};
// AuditAction codes (audit_log_service.dart) where the workbook's action
// is one of them; the others keep their own wording.
const AUDIT_ACTIONS = {
  Login: "LOGIN_SUCCESS",
  Logout: "LOGOUT",
  "Listing suspension": "SUSPEND_LISTING",
  "Analytics report export": "EXPORT_REPORT",
  "Reference price update": "UPDATE_BASELINE_PRICE",
  "Notification sent": "SEND_ANNOUNCEMENT",
};

/** The rows of a sheet as objects by header; blank rows left out. */
function sheetRecords(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return [];
  const header = rows[0].map((h) => (h == null ? "" : String(h).trim()));
  const records = [];
  rows.slice(1).forEach((row, index) => {
    if (!row || row.every((v) => v === null || v === undefined || String(v).trim() === "")) return;
    const record = { __row: index + 2 };
    header.forEach((key, i) => {
      if (!key) return;
      const value = row[i];
      record[key] = typeof value === "string" ? value.trim() : value ?? null;
      if (record[key] === "") record[key] = null;
    });
    records.push(record);
  });
  return records;
}

/**
 * "2026-10-19 02:44:12" (Philippine time, as the workbook writes it) as a
 * Date; "2026-10" as the first of that month. Null when it is not a date.
 */
function manilaDate(text) {
  if (text === null || text === undefined) return null;
  const m = /^(\d{4})-(\d{2})(?:-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?)?$/.exec(String(text).trim());
  if (!m) return null;
  const [, y, mo, d = "01", h = "00", mi = "00", s = "00"] = m;
  const date = new Date(Date.UTC(+y, +mo - 1, +d, +h - 8, +mi, +s));
  // Reject "2026-02-31" and the like: the parts must survive the round trip.
  const back = new Date(date.getTime() + 8 * 3600 * 1000);
  if (back.getUTCFullYear() !== +y || back.getUTCMonth() !== +mo - 1 || back.getUTCDate() !== +d) return null;
  return date;
}

/** The Philippine calendar month of [date], "2026-10". */
function manilaMonth(date) {
  return new Date(date.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 7);
}

/** Firestore id of a commodity's market_prices record (Price Management's). */
function commodityDocId(name) {
  return String(name).toLowerCase().replace(/[^a-z0-9]+/g, "_");
}

/** "Juan Dela Cruz" -> first "Juan", last "Dela Cruz" (particles kept). */
function splitName(full) {
  const parts = String(full || "").trim().split(/\s+/).filter(Boolean);
  if (parts.length <= 1) return { firstName: parts[0] || "", lastName: "" };
  const particles = new Set(["de", "dela", "del", "delos", "san", "santa", "sta.", "sto.", "la", "di"]);
  let cut = parts.length - 1;
  while (cut > 1 && particles.has(parts[cut - 1].toLowerCase())) cut--;
  return { firstName: parts.slice(0, cut).join(" "), lastName: parts.slice(cut).join(" ") };
}

function formatStock(quantity, unit) {
  const q = Number.isInteger(quantity) ? String(quantity) : Number(quantity).toFixed(2);
  return COUNT_UNITS.has(unit) && quantity !== 1 ? `${q} ${unit}s` : `${q} ${unit}`;
}

const yes = (v) => String(v ?? "").trim().toLowerCase() === "yes";
const money = (n) => Math.round(Number(n) * 100) / 100;

/** The app's commodity for a workbook commodity row: name, category, unit. */
function appCommodity(row) {
  const rename = COMMODITY_RENAMES[row.product_name] || {};
  const unit = (rename.unit && rename.unit[row.unit]) || row.unit;
  const category = CATEGORY_RENAMES[row.category] || row.category;
  return { name: rename.name || row.product_name, category, unit };
}

/** The workbook's sheets as records, by sheet name. */
function workbookRecords(sheets) {
  const out = {};
  for (const name of Object.keys(SHEETS)) out[name] = sheetRecords(sheets[name] || []);
  return out;
}

/**
 * Everything wrong with the workbook: [errors] stop the import, [warnings]
 * are reported. Checks columns, ids, every relationship, totals, dates and
 * the order of each order's steps.
 */
function validateWorkbook(sheets) {
  const errors = [];
  const warnings = [];
  const err = (sheet, row, text) => errors.push(`${sheet}${row ? ` row ${row}` : ""}: ${text}`);
  const warn = (sheet, row, text) => warnings.push(`${sheet}${row ? ` row ${row}` : ""}: ${text}`);

  for (const [name, columns] of Object.entries(SHEETS)) {
    const rows = sheets[name];
    if (!rows || rows.length === 0) {
      err(name, null, "sheet is missing or empty.");
      continue;
    }
    const header = (rows[0] || []).map((h) => String(h ?? "").trim());
    for (const column of columns) {
      if (!header.includes(column)) err(name, null, `column "${column}" is missing.`);
    }
  }
  if (errors.length) return { errors, warnings };

  const wb = workbookRecords(sheets);
  const index = {};
  for (const [name, column] of Object.entries(ID_COLUMN)) {
    index[name] = new Map();
    for (const r of wb[name]) {
      const id = r[column];
      if (id === null || id === undefined) err(name, r.__row, `no ${column}.`);
      else if (index[name].has(String(id))) err(name, r.__row, `duplicate ${column} ${id}.`);
      else index[name].set(String(id), r);
    }
  }
  const loc = index.Locations;
  const users = index.Users;
  const verifications = index["Farmer Verifications"];
  const commodities = index.Commodities;
  const products = index.Products;
  const orders = index.Orders;
  const dateOf = (sheet, r, column, required = true) => {
    const value = r[column];
    if (value === null || value === undefined) {
      if (required) err(sheet, r.__row, `${column} is empty.`);
      return null;
    }
    const date = manilaDate(value);
    if (!date) err(sheet, r.__row, `${column} "${value}" is not a date (YYYY-MM-DD HH:MM:SS).`);
    return date;
  };
  const role = (id) => users.get(String(id))?.role;

  for (const r of wb.Locations) {
    if (!r.barangay || !r.municipality || !r.province) err("Locations", r.__row, "barangay, municipality and province are required.");
    if (!yes(r.is_luzon)) err("Locations", r.__row, "AgriTrade+ covers Luzon only (is_luzon is not Yes).");
  }

  for (const r of wb.Users) {
    if (!["Buyer", "Farmer", "Admin"].includes(r.role)) err("Users", r.__row, `unknown role "${r.role}".`);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(r.email || ""))) err("Users", r.__row, `email "${r.email}" is not valid.`);
    if (typeof r.phone === "number") err("Users", r.__row, "phone is stored as a number (its leading 0 is lost); store it as text.");
    if (!(r.account_status in ACCOUNT_STATUSES)) err("Users", r.__row, `unknown account_status "${r.account_status}".`);
    if (r.role !== "Admin" && !loc.has(String(r.location_id))) err("Users", r.__row, `location ${r.location_id} is not in Locations.`);
    dateOf("Users", r, "registered_at");
    if (r.role === "Farmer" && !verifications.has(String(r.user_id))) err("Users", r.__row, `farmer ${r.user_id} has no Farmer Verifications row.`);
  }

  const rsbsaSeen = new Map();
  for (const r of wb["Farmer Verifications"]) {
    if (role(r.farmer_id) !== "Farmer") err("Farmer Verifications", r.__row, `${r.farmer_id} is not a farmer in Users.`);
    if (!(r.verification_status in VERIFICATION_STATUSES)) err("Farmer Verifications", r.__row, `unknown verification_status "${r.verification_status}".`);
    if (typeof r.rsbsa_no === "number") {
      err("Farmer Verifications", r.__row, "rsbsa_no is stored as a number (leading zeros are lost); store it as text.");
    } else if (!/^\d{15,17}$/.test(String(r.rsbsa_no || ""))) {
      err("Farmer Verifications", r.__row, `rsbsa_no "${r.rsbsa_no}" must be 15–17 digits.`);
    } else if (rsbsaSeen.has(r.rsbsa_no)) {
      err("Farmer Verifications", r.__row, `rsbsa_no ${r.rsbsa_no} is also used by ${rsbsaSeen.get(r.rsbsa_no)}.`);
    } else rsbsaSeen.set(r.rsbsa_no, r.farmer_id);
    const user = users.get(String(r.farmer_id));
    if (user && user.location_id !== r.location_id) err("Farmer Verifications", r.__row, "location differs from the farmer's Users row.");
    dateOf("Farmer Verifications", r, "submitted_at");
    if (r.verification_status !== "Pending") {
      const reviewed = dateOf("Farmer Verifications", r, "reviewed_at");
      if (role(r.reviewed_by) !== "Admin") err("Farmer Verifications", r.__row, `reviewed_by ${r.reviewed_by} is not an admin.`);
      const submitted = manilaDate(r.submitted_at);
      if (reviewed && submitted && reviewed < submitted) err("Farmer Verifications", r.__row, "reviewed before it was submitted.");
    }
  }

  for (const r of wb.Commodities) {
    const refused = REFUSED_COMMODITIES[String(r.product_name || "").toLowerCase()];
    if (refused) err("Commodities", r.__row, refused);
    const app = appCommodity(r);
    if (!APP_CATEGORIES.includes(app.category)) err("Commodities", r.__row, `category "${r.category}" is not an AgriTrade+ category.`);
    if (!(Number(r.reference_price_php) > 0)) err("Commodities", r.__row, "reference_price_php must be above 0.");
    if (/official|da[- ]issued|certified/i.test(String(r.reference_status || "")) && !/not/i.test(String(r.reference_status))) {
      err("Commodities", r.__row, "official/government-certified prices are not imported; mark it an internal reference.");
    }
  }

  const approved = (farmerId) => verifications.get(String(farmerId))?.verification_status === "Approved";
  for (const r of wb.Products) {
    const c = commodities.get(String(r.commodity_id));
    if (!c) err("Products", r.__row, `commodity ${r.commodity_id} is not in Commodities.`);
    else {
      if (c.product_name !== r.product_name) err("Products", r.__row, `name "${r.product_name}" differs from its commodity "${c.product_name}".`);
      if (c.unit !== r.unit) err("Products", r.__row, `unit "${r.unit}" differs from its commodity's "${c.unit}".`);
      if (c.category !== r.category) err("Products", r.__row, `category "${r.category}" differs from its commodity's "${c.category}".`);
    }
    if (role(r.farmer_id) !== "Farmer") err("Products", r.__row, `${r.farmer_id} is not a farmer.`);
    else if (!approved(r.farmer_id)) err("Products", r.__row, `${r.farmer_id} is not an approved farmer, so cannot list products.`);
    else if (users.get(String(r.farmer_id)).location_id !== r.seller_location_id) err("Products", r.__row, "seller_location_id differs from the farmer's location.");
    if (!(Number(r.price_php) > 0)) err("Products", r.__row, "price_php must be above 0.");
    if (!Number.isInteger(r.listed_stock) || r.listed_stock < 0) err("Products", r.__row, "listed_stock must be a whole number, 0 or more.");
    if (!["Active", "Archived", "Suspended"].includes(r.listing_status)) err("Products", r.__row, `unknown listing_status "${r.listing_status}".`);
    if (!yes(r.delivery_supported) && !yes(r.pickup_supported)) err("Products", r.__row, "neither delivery nor pick-up is offered.");
    const posted = dateOf("Products", r, "posted_at");
    const farmer = verifications.get(String(r.farmer_id));
    const approvedAt = farmer ? manilaDate(farmer.reviewed_at) : null;
    if (posted && approvedAt && posted < approvedAt) warn("Products", r.__row, `posted before ${r.farmer_id} was approved.`);
    if (yes(r.wholesale_enabled) && c && ["head", "piece"].includes(c.unit)) err("Products", r.__row, "a listing sold per head or piece has no wholesale.");
  }

  for (const r of wb.Orders) {
    const p = products.get(String(r.product_id));
    const status = ORDER_STATUSES[r.status];
    if (!status) err("Orders", r.__row, `unknown status "${r.status}".`);
    if (role(r.buyer_id) !== "Buyer") err("Orders", r.__row, `${r.buyer_id} is not a buyer.`);
    else if (users.get(String(r.buyer_id)).location_id !== r.buyer_location_id) warn("Orders", r.__row, "buyer_location_id differs from the buyer's saved location (the order's own is used).");
    if (!loc.has(String(r.buyer_location_id))) err("Orders", r.__row, `location ${r.buyer_location_id} is not in Locations.`);
    if (!p) err("Orders", r.__row, `product ${r.product_id} is not in Products.`);
    else {
      if (p.farmer_id !== r.farmer_id) err("Orders", r.__row, `farmer ${r.farmer_id} does not sell ${r.product_id}.`);
      if (p.category !== r.category) err("Orders", r.__row, `category "${r.category}" differs from the product's.`);
      if (p.unit !== r.unit) err("Orders", r.__row, `unit "${r.unit}" differs from the product's.`);
      if (r.fulfilment === "Delivery" && !yes(p.delivery_supported)) err("Orders", r.__row, "delivery on a listing without delivery.");
      if (r.fulfilment === "Pick-up" && !yes(p.pickup_supported)) err("Orders", r.__row, "pick-up on a listing without pick-up.");
    }
    if (!["Delivery", "Pick-up"].includes(r.fulfilment)) err("Orders", r.__row, `unknown fulfilment "${r.fulfilment}".`);
    if (!(Number(r.quantity) > 0)) err("Orders", r.__row, "quantity must be above 0.");
    if (Math.abs(Number(r.quantity) * Number(r.unit_price_php) - Number(r.total_php)) > 0.011) {
      err("Orders", r.__row, `total ${r.total_php} is not quantity × unit price (${money(r.quantity * r.unit_price_php)}).`);
    }
    if (p && ["head", "piece"].includes(p.unit) && !Number.isInteger(r.quantity)) err("Orders", r.__row, "animals are sold whole.");
    const placed = dateOf("Orders", r, "placed_at");
    const steps = [
      ["confirmed_at", ["confirmed", "shipped", "completed"]],
      ["shipped_at", ["shipped"]],
      ["completed_at", ["completed"]],
      ["cancelled_at", ["cancelled"]],
    ];
    let previous = placed;
    for (const [column, needs] of steps) {
      const required = needs.includes(status);
      const date = dateOf("Orders", r, column, required);
      if (date && !required && column !== "confirmed_at" && column !== "shipped_at") {
        err("Orders", r.__row, `${column} is set on a ${r.status} order.`);
      }
      if (date && previous && date < previous && column !== "cancelled_at") err("Orders", r.__row, `${column} is before the step before it.`);
      if (date && column !== "cancelled_at") previous = date;
    }
    const cancelled = manilaDate(r.cancelled_at);
    if (cancelled && placed && cancelled < placed) err("Orders", r.__row, "cancelled before it was placed.");
    const buyer = users.get(String(r.buyer_id));
    const registered = buyer ? manilaDate(buyer.registered_at) : null;
    if (placed && registered && placed < registered) warn("Orders", r.__row, `placed before ${r.buyer_id} registered.`);
    const posted = p ? manilaDate(p.posted_at) : null;
    if (placed && posted && placed < posted) warn("Orders", r.__row, `placed before ${r.product_id} was posted.`);
  }

  const reviewedOrders = new Set();
  for (const r of wb.Reviews) {
    const o = orders.get(String(r.order_id));
    if (!o) err("Reviews", r.__row, `order ${r.order_id} is not in Orders.`);
    else {
      if (o.status !== "Completed") err("Reviews", r.__row, `order ${r.order_id} is ${o.status}; only completed orders are reviewed.`);
      if (o.buyer_id !== r.buyer_id || o.product_id !== r.product_id || o.farmer_id !== r.farmer_id) {
        err("Reviews", r.__row, `buyer, farmer or product differ from order ${r.order_id}.`);
      }
      const done = manilaDate(o.completed_at);
      const at = dateOf("Reviews", r, "reviewed_at");
      if (done && at && at < done) err("Reviews", r.__row, "reviewed before the order was completed.");
    }
    if (reviewedOrders.has(r.order_id)) err("Reviews", r.__row, `order ${r.order_id} has two reviews (one per order).`);
    reviewedOrders.add(r.order_id);
    if (!Number.isInteger(r.rating) || r.rating < 1 || r.rating > 5) err("Reviews", r.__row, "rating must be a whole number from 1 to 5.");
    if (yes(r.photo_attached)) warn("Reviews", r.__row, "photo_attached is Yes but the workbook has no photo file; imported without a photo.");
  }

  const reports = index.Reports;
  for (const r of wb.Reports) {
    const p = products.get(String(r.reported_product_id));
    if (!p) err("Reports", r.__row, `product ${r.reported_product_id} is not in Products.`);
    else if (p.farmer_id !== r.reported_farmer_id) err("Reports", r.__row, `${r.reported_product_id} is not ${r.reported_farmer_id}'s.`);
    if (role(r.reporter_buyer_id) !== "Buyer") err("Reports", r.__row, `${r.reporter_buyer_id} is not a buyer.`);
    if (!(r.report_status in REPORT_STATUSES)) err("Reports", r.__row, `unknown report_status "${r.report_status}".`);
    if (r.report_status !== "Pending" && role(r.assigned_admin_id) !== "Admin") err("Reports", r.__row, "a report under review or resolved needs an admin.");
    dateOf("Reports", r, "reported_at");
  }
  for (const r of wb.Violations) {
    const rep = reports.get(String(r.report_id));
    if (!rep) err("Violations", r.__row, `report ${r.report_id} is not in Reports.`);
    else {
      if (rep.reported_farmer_id !== r.farmer_id || rep.reported_product_id !== r.product_id) err("Violations", r.__row, `farmer or product differ from report ${r.report_id}.`);
      if (rep.report_status === "Pending") warn("Violations", r.__row, `report ${r.report_id} is still Pending.`);
      const reported = manilaDate(rep.reported_at);
      const at = manilaDate(r.action_at);
      if (reported && at && at < reported) err("Violations", r.__row, "action taken before the report was made.");
    }
    if (!(r.action in VIOLATION_ACTIONS)) err("Violations", r.__row, `unknown action "${r.action}".`);
    if (role(r.admin_id) !== "Admin") err("Violations", r.__row, `${r.admin_id} is not an admin.`);
    dateOf("Violations", r, "action_at");
  }
  const violationReports = wb.Violations.map((v) => v.report_id);
  if (new Set(violationReports).size !== violationReports.length) err("Violations", null, "a report has more than one violation (the app keeps one per report).");

  for (const r of wb["Price History"]) {
    const c = commodities.get(String(r.commodity_id));
    if (!c) err("Price History", r.__row, `commodity ${r.commodity_id} is not in Commodities.`);
    else if (c.unit !== r.unit) err("Price History", r.__row, `unit "${r.unit}" differs from the commodity's "${c.unit}".`);
    if (!(Number(r.price_php) > 0)) err("Price History", r.__row, "price_php must be above 0.");
    if (yes(r.official_price)) err("Price History", r.__row, "official (government-certified) prices are not imported.");
    if (!/^\d{4}-\d{2}$/.test(String(r.period || ""))) err("Price History", r.__row, `period "${r.period}" is not YYYY-MM.`);
    dateOf("Price History", r, "recorded_at");
  }
  for (const r of wb["Price Changes"]) {
    if (!commodities.has(String(r.commodity_id))) err("Price Changes", r.__row, `commodity ${r.commodity_id} is not in Commodities.`);
    if (!(Number(r.new_price_php) > 0)) err("Price Changes", r.__row, "new_price_php must be above 0.");
    if (role(r.changed_by) !== "Admin") err("Price Changes", r.__row, `${r.changed_by} is not an admin.`);
    dateOf("Price Changes", r, "changed_at");
  }
  for (const r of wb["Search Events"]) {
    if (role(r.buyer_id) !== "Buyer") err("Search Events", r.__row, `${r.buyer_id} is not a buyer.`);
    if (!loc.has(String(r.buyer_location_id))) err("Search Events", r.__row, `location ${r.buyer_location_id} is not in Locations.`);
    const term = String(r.search_term || "").trim();
    if (term.length < 2 || term.length > 60) err("Search Events", r.__row, "search_term must be 2–60 characters.");
    dateOf("Search Events", r, "searched_at");
  }
  const conversations = index.Conversations;
  for (const r of wb.Conversations) {
    if (role(r.buyer_id) !== "Buyer") err("Conversations", r.__row, `${r.buyer_id} is not a buyer.`);
    if (role(r.farmer_id) !== "Farmer") err("Conversations", r.__row, `${r.farmer_id} is not a farmer.`);
    const p = products.get(String(r.product_id));
    if (!p) err("Conversations", r.__row, `product ${r.product_id} is not in Products.`);
    else if (p.farmer_id !== r.farmer_id) err("Conversations", r.__row, `${r.product_id} is not ${r.farmer_id}'s.`);
    dateOf("Conversations", r, "started_at");
  }
  for (const r of wb.Messages) {
    const c = conversations.get(String(r.conversation_id));
    if (!c) err("Messages", r.__row, `conversation ${r.conversation_id} is not in Conversations.`);
    else if (r.sender_id !== c.buyer_id && r.sender_id !== c.farmer_id) err("Messages", r.__row, `${r.sender_id} is not in conversation ${r.conversation_id}.`);
    else {
      const started = manilaDate(c.started_at);
      const at = manilaDate(r.sent_at);
      if (started && at && at < started) err("Messages", r.__row, "sent before the conversation started.");
    }
    if (r.message_type !== "Text") err("Messages", r.__row, `message_type "${r.message_type}": only text messages can be imported (no files in the workbook).`);
    const body = String(r.body || "").trim();
    if (!body) err("Messages", r.__row, "body is empty.");
    if (body.length > 1000) err("Messages", r.__row, "body is over the app's 1,000 characters.");
    dateOf("Messages", r, "sent_at");
  }
  for (const c of wb.Conversations) {
    if (!wb.Messages.some((m) => m.conversation_id === c.conversation_id)) {
      warn("Conversations", c.__row, `${c.conversation_id} has no messages; the app keeps no empty chats, so it is left out.`);
    }
  }
  for (const r of wb.Notifications) {
    if (!users.has(String(r.user_id))) err("Notifications", r.__row, `${r.user_id} is not in Users.`);
    else if (role(r.user_id) === "Admin") err("Notifications", r.__row, "admin accounts are not imported, so neither are their notifications.");
    if (!(r.event_type in NOTIFICATION_TYPES)) err("Notifications", r.__row, `unknown event_type "${r.event_type}".`);
    if (r.related_order_id && !orders.has(String(r.related_order_id))) err("Notifications", r.__row, `order ${r.related_order_id} is not in Orders.`);
    dateOf("Notifications", r, "created_at");
  }
  for (const r of wb["Audit Logs"]) {
    if (role(r.admin_id) !== "Admin") err("Audit Logs", r.__row, `${r.admin_id} is not an admin.`);
    dateOf("Audit Logs", r, "at");
  }
  return { errors, warnings };
}

/**
 * The documents to write, in the order they depend on each other:
 * { path, data } with dates as Date objects. [includeAuditLogs] adds the
 * workbook's admin activity to audit_logs (off unless asked for: see the
 * script's --include-audit-logs).
 */
function buildPlan(sheets, { batchId = BATCH_ID, includeAuditLogs = false, photoUrls = {} } = {}) {
  const wb = workbookRecords(sheets);
  // [photoUrls]: a photo's address per commodity record id ("corn",
  // "sweet_potato"), from the script's --photos; "" where there is none.
  const photoOf = (name) => photoUrls[commodityDocId(name)] || "";
  const byId = (name) => new Map(wb[name].map((r) => [String(r[ID_COLUMN[name]]), r]));
  const loc = byId("Locations");
  const users = byId("Users");
  const verifications = byId("Farmer Verifications");
  const commodities = byId("Commodities");
  const products = byId("Products");
  const orders = byId("Orders");
  const stamp = (sourceId) => ({ importBatch: batchId, importSourceId: sourceId });
  const adminName = (id) => users.get(String(id))?.display_name || null;
  const nameOf = (id) => users.get(String(id))?.display_name || "";
  const plan = [];
  const add = (path, data) => plan.push({ path, data });

  // Every delivery listing reaches every town a buyer in the workbook is
  // in ("Selected Luzon areas only"), so no imported delivery order is
  // outside its listing's coverage (notifyNewOrder would turn it away).
  const towns = [];
  for (const l of wb.Locations) {
    if (!towns.some((t) => t.name === l.municipality && t.province === l.province)) {
      towns.push({ name: l.municipality, province: l.province });
    }
  }

  // Ratings, review counts and completed-order counts, as the server
  // triggers keep them (recomputeProductReviewStats, recountCompletedOrders).
  const reviewsByProduct = new Map();
  const reviewsBySeller = new Map();
  for (const r of wb.Reviews) {
    for (const [map, key] of [[reviewsByProduct, r.product_id], [reviewsBySeller, r.farmer_id]]) {
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(r.rating);
    }
  }
  const ratingOf = (map, key) => {
    const list = map.get(key) || [];
    return { rating: list.length ? list.reduce((s, n) => s + n, 0) / list.length : 0, reviewCount: list.length };
  };
  const completedByProduct = new Map();
  for (const o of wb.Orders) {
    if (o.status === "Completed") completedByProduct.set(o.product_id, (completedByProduct.get(o.product_id) || 0) + 1);
  }
  const reviewByOrder = new Map(wb.Reviews.map((r) => [r.order_id, r]));
  const buyerReviewCount = new Map();
  for (const r of wb.Reviews) buyerReviewCount.set(r.buyer_id, (buyerReviewCount.get(r.buyer_id) || 0) + 1);

  // 1. Commodities (Price Management) and their dated reference prices.
  const historyByCommodity = new Map();
  for (const h of wb["Price History"]) {
    if (!historyByCommodity.has(h.commodity_id)) historyByCommodity.set(h.commodity_id, []);
    historyByCommodity.get(h.commodity_id).push(h);
  }
  for (const c of wb.Commodities) {
    const app = appCommodity(c);
    const id = commodityDocId(app.name);
    const history = historyByCommodity.get(c.commodity_id) || [];
    const latest = history.map((h) => manilaDate(h.recorded_at)).filter(Boolean).sort((a, b) => b - a)[0];
    add(`market_prices/${id}`, {
      name: app.name,
      category: app.category,
      unit: app.unit,
      baselinePrice: money(c.reference_price_php),
      previousBaselinePrice: null,
      effectiveDate: latest || manilaDate("2026-11-01"),
      isActive: true,
      // An internal reference figure, never a government-issued price.
      source: "Internal reference price (not DA-issued)",
      isTestData: true,
      createdAt: latest || manilaDate("2026-08-01"),
      updatedAt: latest || manilaDate("2026-08-01"),
      updatedBy: "AgriTrade+ records import",
      ...stamp(c.commodity_id),
    });
  }
  for (const h of wb["Price History"]) {
    const c = commodities.get(String(h.commodity_id));
    const app = appCommodity(c);
    const at = manilaDate(h.recorded_at);
    add(`market_prices/${commodityDocId(app.name)}/history/${h.price_record_id}`, {
      price: money(h.price_php),
      unit: app.unit,
      effectiveDate: manilaDate(h.period) || at,
      recordedAt: at,
      recordedBy: "Internal price reference",
      source: "Internal reference price (not DA-issued)",
      ...stamp(h.price_record_id),
    });
  }
  for (const p of wb["Price Changes"]) {
    const c = commodities.get(String(p.commodity_id));
    const app = appCommodity(c);
    const at = manilaDate(p.changed_at);
    add(`market_prices/${commodityDocId(app.name)}/history/${p.change_id}`, {
      price: money(p.new_price_php),
      previousPrice: money(p.old_price_php),
      unit: app.unit,
      effectiveDate: at,
      recordedAt: at,
      recordedBy: adminName(p.changed_by) || p.changed_by,
      reason: p.change_reason || null,
      source: "Internal reference price (not DA-issued)",
      ...stamp(p.change_id),
    });
  }

  // 2. Accounts. Admin rows are not imported: an admin is a real login
  // with a role, never a record written by a script. Their names still
  // show where they reviewed or acted.
  for (const u of wb.Users) {
    if (u.role === "Admin") continue;
    const place = loc.get(String(u.location_id));
    const { firstName, lastName } = splitName(u.display_name);
    const created = manilaDate(u.registered_at);
    const base = {
      role: u.role.toLowerCase(),
      fullName: u.display_name,
      name: u.display_name,
      firstName,
      lastName,
      email: String(u.email).toLowerCase(),
      mobileNumber: String(u.phone || ""),
      accountStatus: ACCOUNT_STATUSES[u.account_status],
      barangay: place.barangay,
      municipality: place.municipality,
      province: place.province,
      region: place.region,
      createdAt: created,
      ...stamp(u.user_id),
    };
    if (u.role === "Buyer") {
      add(`users/${u.user_id}`, {
        ...base,
        approvalStatus: "approved",
        isVerified: true,
        trustedBuyerReviewCount: buyerReviewCount.get(u.user_id) || 0,
        trustedBuyer: (buyerReviewCount.get(u.user_id) || 0) >= 3,
      });
      continue;
    }
    const v = verifications.get(String(u.user_id));
    const status = VERIFICATION_STATUSES[v.verification_status];
    const reviewed = status === "pending" ? null : manilaDate(v.reviewed_at);
    add(`users/${u.user_id}`, {
      ...base,
      approvalStatus: status,
      isVerified: status === "approved",
      rsbaNumber: String(v.rsbsa_no),
      hasVerificationDoc: false,
      ...(reviewed ? { reviewedAt: reviewed, reviewedBy: v.reviewed_by, reviewedByName: adminName(v.reviewed_by) } : {}),
      ...(status === "approved" ? { verifiedAt: reviewed } : {}),
      ...ratingOf(reviewsBySeller, u.user_id),
    });
    add(`verificationDocs/${u.user_id}`, {
      userId: u.user_id,
      fullName: u.display_name,
      applicationId: v.application_id,
      rsbaNumber: String(v.rsbsa_no),
      status,
      documentStatus: v.document_status || null,
      submittedAt: manilaDate(v.submitted_at),
      ...(reviewed ? { reviewedAt: reviewed, reviewedBy: v.reviewed_by, reviewedByName: adminName(v.reviewed_by) } : {}),
      ...(status === "rejected" ? { rejectionReason: v.document_status || "Rejected" } : {}),
      ...stamp(v.application_id),
    });
  }

  // 3. Listings.
  for (const p of wb.Products) {
    const app = appCommodity(commodities.get(String(p.commodity_id)));
    const place = loc.get(String(p.seller_location_id));
    const delivery = yes(p.delivery_supported);
    const status = p.listing_status;
    const created = manilaDate(p.posted_at);
    add(`products/${p.product_id}`, {
      farmerId: p.farmer_id,
      farmerName: nameOf(p.farmer_id),
      name: app.name,
      category: app.category,
      commodity: app.name,
      unit: app.unit,
      ...(app.category === "Livestock" ? { sellingOption: "live" } : {}),
      price: money(p.price_php),
      retailPrice: money(p.price_php),
      // The workbook gives no wholesale price or minimum, so none is made
      // up: the listings are retail until their farmer sets wholesale.
      wholesaleEnabled: false,
      wholesalePrice: null,
      wholesaleMinimumQuantity: null,
      retailMaximumQuantity: null,
      quantity: p.listed_stock,
      stockBaseline: p.listed_stock,
      description: "",
      // A photo only when one was supplied for the commodity (--photos).
      imageUrls: photoOf(app.name) ? [photoOf(app.name)] : [],
      imageUrl: photoOf(app.name),
      deliveryAvailable: delivery,
      pickupOnly: yes(p.pickup_supported),
      ...(delivery
        ? {
            deliveryCoverage: {
              type: "custom",
              areas: towns,
              feeType: "arranged",
              originBarangay: place.barangay,
              originMunicipality: place.municipality,
              originProvince: place.province,
            },
          }
        : {}),
      isArchived: status === "Archived",
      isSuspended: status === "Suspended",
      ...(status === "Suspended" ? { moderationStatus: "removed" } : {}),
      ...ratingOf(reviewsByProduct, p.product_id),
      completedOrderCount: completedByProduct.get(p.product_id) || 0,
      createdAt: created,
      updatedAt: created,
      ...stamp(p.product_id),
    });
  }

  // 4. Orders, each as OrderService writes one (stock taken on confirming).
  for (const o of wb.Orders) {
    const p = products.get(String(o.product_id));
    const app = appCommodity(commodities.get(String(p.commodity_id)));
    const place = loc.get(String(o.buyer_location_id));
    const status = ORDER_STATUSES[o.status];
    const placed = manilaDate(o.placed_at);
    const confirmed = manilaDate(o.confirmed_at);
    const shipped = manilaDate(o.shipped_at);
    const completed = manilaDate(o.completed_at);
    const cancelled = manilaDate(o.cancelled_at);
    const last = [placed, confirmed, shipped, completed, cancelled].filter(Boolean).sort((a, b) => b - a)[0];
    const review = reviewByOrder.get(o.order_id);
    const delivery = o.fulfilment === "Delivery";
    const total = money(o.total_php);
    add(`orders/${o.order_id}`, {
      stockOnConfirm: true,
      sellerId: o.farmer_id,
      sellerName: nameOf(o.farmer_id),
      buyerId: o.buyer_id,
      buyerName: nameOf(o.buyer_id),
      buyerAddress: `${place.barangay}, ${place.municipality}, ${place.province}`,
      buyerBarangay: place.barangay,
      buyerMunicipality: place.municipality,
      buyerProvince: place.province,
      productId: o.product_id,
      productName: app.name,
      category: app.category,
      commodity: app.name,
      imageUrl: photoOf(app.name),
      quantity: o.quantity,
      unit: app.unit,
      quantityLabel: formatStock(o.quantity, app.unit),
      pricingType: "retail",
      pricePerUnit: money(o.unit_price_php),
      unitPrice: money(o.unit_price_php),
      subtotal: total,
      total,
      deliveryMethod: delivery ? "delivery" : "pickup",
      ...(delivery ? { deliveryArrangement: "standard", deliveryFeeType: "arranged", deliveryFee: null, grandTotal: null } : {}),
      status,
      createdAt: placed,
      updatedAt: last,
      ...(confirmed ? { confirmedAt: confirmed } : {}),
      // Stock left the listing when the farmer confirmed; a cancelled
      // order had it given back, so it carries no mark.
      ...(confirmed && status !== "cancelled" ? { stockDeductedAt: confirmed } : {}),
      ...(shipped ? { shippedAt: shipped } : {}),
      ...(completed ? { completedAt: completed } : {}),
      ...(cancelled ? { cancelledAt: cancelled } : {}),
      ...(review ? { reviewedAt: manilaDate(review.reviewed_at), reviewRating: review.rating } : {}),
      ...stamp(o.order_id),
    });
  }

  // 5. Reviews: one per order, under the order's id (ReviewService).
  for (const r of wb.Reviews) {
    const p = products.get(String(r.product_id));
    const app = appCommodity(commodities.get(String(p.commodity_id)));
    add(`productReviews/${r.order_id}`, {
      orderId: r.order_id,
      productId: r.product_id,
      productName: app.name,
      sellerId: r.farmer_id,
      buyerId: r.buyer_id,
      buyerName: nameOf(r.buyer_id),
      rating: r.rating,
      comment: String(r.review_text || "").trim(),
      imageUrl: "",
      imageUrls: [],
      createdAt: manilaDate(r.reviewed_at),
      ...stamp(r.review_id),
    });
  }

  // 6. Reports and the violations confirmed on them (one per report,
  // under the report's id, as the Moderation Queue keeps them).
  const violationByReport = new Map(wb.Violations.map((v) => [v.report_id, v]));
  for (const r of wb.Reports) {
    const p = products.get(String(r.reported_product_id));
    const app = appCommodity(commodities.get(String(p.commodity_id)));
    const status = REPORT_STATUSES[r.report_status];
    const v = violationByReport.get(r.report_id);
    const action = v ? VIOLATION_ACTIONS[v.action] : null;
    add(`reports/${r.report_id}`, {
      issueType: r.issue_type,
      description: "",
      reporterId: r.reporter_buyer_id,
      reporterName: nameOf(r.reporter_buyer_id),
      reporterRole: "buyer",
      targetType: "listing",
      productId: r.reported_product_id,
      productName: app.name,
      farmerId: r.reported_farmer_id,
      farmerName: nameOf(r.reported_farmer_id),
      reportedUserId: r.reported_farmer_id,
      reportedUserName: nameOf(r.reported_farmer_id),
      status,
      createdAt: manilaDate(r.reported_at),
      ...(r.assigned_admin_id ? { reviewedBy: r.assigned_admin_id, reviewedByName: adminName(r.assigned_admin_id) } : {}),
      ...(v ? { reviewedAt: manilaDate(v.action_at), moderationAction: action.code } : {}),
      ...(r.resolution ? { resolution: r.resolution } : {}),
      ...stamp(r.report_id),
    });
  }
  for (const v of wb.Violations) {
    const report = wb.Reports.find((r) => r.report_id === v.report_id);
    const action = VIOLATION_ACTIONS[v.action];
    add(`violations/${v.report_id}`, {
      reportedUserId: v.farmer_id,
      reportedUserRole: "farmer",
      sourceReportId: v.report_id,
      violationType: v.violation_type || report.issue_type,
      reason: v.action,
      evidence: null,
      relatedListingId: v.product_id,
      relatedOrderId: null,
      relatedConversationId: null,
      relatedReviewId: null,
      actionTaken: action.code,
      actionLabel: v.action,
      severity: action.severity,
      confirmedBy: v.admin_id,
      confirmedByName: adminName(v.admin_id),
      confirmedAt: manilaDate(v.action_at),
      status: "confirmed",
      ...stamp(v.violation_id),
    });
  }

  // 7. Searches, for discovery analytics only (never the Demand Heatmap).
  // They carry `buyerId`, not `userId`: aggregateSearchTrend counts an
  // event with a userId under the day it runs, so 900 past searches would
  // all land on today in every buyer's Trending Searches.
  for (const s of wb["Search Events"]) {
    const place = loc.get(String(s.buyer_location_id));
    add(`searchEvents/${s.search_id}`, {
      query: String(s.search_term).trim().toLowerCase().replace(/\s+/g, " "),
      buyerId: s.buyer_id,
      category: CATEGORY_RENAMES[s.category] || s.category || null,
      buyerBarangay: place.barangay,
      buyerMunicipality: place.municipality,
      createdAt: manilaDate(s.searched_at),
      ...stamp(s.search_id),
    });
  }

  // 8. Chats: one conversation per buyer and farmer, under the app's id
  // (MessageService.conversationIdFor: the two ids sorted). Two workbook
  // conversations between the same pair become one thread.
  const messagesByPair = new Map();
  const convById = new Map(wb.Conversations.map((c) => [c.conversation_id, c]));
  const pairOf = (c) => [c.buyer_id, c.farmer_id].sort().join("_");
  for (const m of wb.Messages) {
    const c = convById.get(m.conversation_id);
    const pair = pairOf(c);
    if (!messagesByPair.has(pair)) messagesByPair.set(pair, { convs: new Set(), messages: [] });
    messagesByPair.get(pair).convs.add(c.conversation_id);
    messagesByPair.get(pair).messages.push(m);
  }
  for (const [pair, { convs, messages }] of messagesByPair) {
    const threads = [...convs].map((id) => convById.get(id)).sort((a, b) => manilaDate(a.started_at) - manilaDate(b.started_at));
    const first = threads[0];
    const latestThread = threads[threads.length - 1];
    messages.sort((a, b) => manilaDate(a.sent_at) - manilaDate(b.sent_at));
    const lastMessage = messages[messages.length - 1];
    const p = products.get(String(latestThread.product_id));
    const app = appCommodity(commodities.get(String(p.commodity_id)));
    add(`conversations/${pair}`, {
      participants: [first.buyer_id, first.farmer_id],
      participantNames: { [first.buyer_id]: nameOf(first.buyer_id), [first.farmer_id]: nameOf(first.farmer_id) },
      farmerId: first.farmer_id,
      farmerName: nameOf(first.farmer_id),
      productId: latestThread.product_id,
      productName: app.name,
      productImageUrl: photoOf(app.name),
      productPrice: `₱${money(p.price_php).toFixed(2)} / ${app.unit}`,
      unit: app.unit,
      retailPrice: money(p.price_php),
      deliveryAvailable: yes(p.delivery_supported),
      pickupOnly: yes(p.pickup_supported),
      lastMessage: String(lastMessage.body).trim(),
      lastMessageTime: manilaDate(lastMessage.sent_at),
      lastSenderId: lastMessage.sender_id,
      hasMessages: true,
      createdAt: manilaDate(first.started_at),
      importSourceIds: threads.map((t) => t.conversation_id),
      importBatch: batchId,
      importSourceId: threads.map((t) => t.conversation_id).join("+"),
    });
    for (const m of messages) {
      add(`conversations/${pair}/messages/${m.message_id}`, {
        senderId: m.sender_id,
        text: String(m.body).trim(),
        createdAt: manilaDate(m.sent_at),
        ...stamp(m.message_id),
      });
    }
  }

  // 9. Notifications, in each account's own list.
  for (const n of wb.Notifications) {
    const kind = NOTIFICATION_TYPES[n.event_type];
    const orderId = n.related_order_id ? String(n.related_order_id) : null;
    const order = orderId ? orders.get(orderId) : null;
    const product = order ? appCommodity(commodities.get(String(products.get(String(order.product_id)).commodity_id))).name : null;
    const body = {
      order_status: order ? `Order #${orderId} (${product}) is now ${order.status}.` : "An order was updated.",
      new_order: order ? `Order #${orderId}: ${formatStock(order.quantity, order.unit)} of ${product}.` : "You have a new order.",
      chat_message: "You have a new message.",
      review: order ? `A review was posted for ${product} (order #${orderId}).` : "A review was posted.",
    }[kind.type];
    add(`notifications/${n.user_id}/items/${n.notification_id}`, {
      recipientId: n.user_id,
      title: kind.title,
      body,
      type: kind.type,
      category: kind.category,
      relatedId: orderId,
      data: orderId ? { orderId } : {},
      read: yes(n.is_read),
      deliveryChannels: ["in_app"],
      createdAt: manilaDate(n.created_at),
      ...stamp(n.notification_id),
    });
  }

  // 10. The admins' activity, only when asked for.
  if (includeAuditLogs) {
    for (const a of wb["Audit Logs"]) {
      const admin = users.get(String(a.admin_id));
      const target = [a.target_type, a.target_id].filter((x) => x && x !== "System").join(" ");
      add(`audit_logs/${a.audit_id}`, {
        action: AUDIT_ACTIONS[a.action] || a.action.toUpperCase().replace(/[^A-Z0-9]+/g, "_"),
        details: `${a.action}${target ? ` (${target})` : ""}.`,
        device: { browser: "Unknown", os: "Unknown" },
        ip: a.ip_address || null,
        location: "Unknown",
        timestamp: manilaDate(a.at),
        adminId: a.admin_id,
        adminName: admin.display_name,
        adminEmail: admin.email,
        attemptedEmail: null,
        result: a.result || null,
        ...stamp(a.audit_id),
      });
    }
  }
  return plan;
}

/** How many documents [plan] writes, per top-level collection (and subcollection). */
function planCounts(plan) {
  const counts = {};
  for (const { path } of plan) {
    const parts = path.split("/");
    const key = parts.length > 2 ? `${parts[0]}/*/${parts[2]}` : parts[0];
    counts[key] = (counts[key] || 0) + 1;
  }
  return counts;
}

/**
 * The dashboard's numbers computed from imported documents (the plan, or
 * what was read back from Firestore): { path, data } entries, dates as
 * Date or anything with toDate(). Completed orders only, by the order's
 * own buyer area and completion month (the app's rules).
 */
function summarize(docs) {
  const toDate = (v) => (v instanceof Date ? v : v && typeof v.toDate === "function" ? v.toDate() : null);
  const top = (name) => docs.filter((d) => d.path.split("/").length === 2 && d.path.startsWith(`${name}/`)).map((d) => d.data);
  const users = top("users");
  const orders = top("orders");
  const products = top("products");
  const completed = orders.filter((o) => o.status === "completed");
  const buyerSet = (list) => new Set(list.map((o) => o.buyerId)).size;
  const areaOf = (o) => `${o.buyerBarangay}, ${o.buyerMunicipality}`;
  const group = (list, key) => {
    const map = new Map();
    for (const item of list) {
      const k = key(item);
      if (!map.has(k)) map.set(k, []);
      map.get(k).push(item);
    }
    return map;
  };
  const monthly = {};
  for (const [month, list] of group(completed, (o) => manilaMonth(toDate(o.completedAt)))) {
    monthly[month] = { completedOrders: list.length, completedSales: money(list.reduce((s, o) => s + o.total, 0)) };
  }
  for (const [month, list] of group(orders, (o) => manilaMonth(toDate(o.createdAt)))) {
    monthly[month] = { ...(monthly[month] || { completedOrders: 0, completedSales: 0 }), allOrders: list.length };
  }
  return {
    buyers: users.filter((u) => u.role === "buyer").length,
    farmers: users.filter((u) => u.role === "farmer").length,
    approvedFarmers: users.filter((u) => u.role === "farmer" && u.approvalStatus === "approved").length,
    pendingFarmers: users.filter((u) => u.role === "farmer" && u.approvalStatus === "pending").length,
    rejectedFarmers: users.filter((u) => u.role === "farmer" && u.approvalStatus === "rejected").length,
    listings: products.length,
    activeListings: products.filter((p) => !p.isArchived && !p.isSuspended).length,
    allOrders: orders.length,
    completedOrders: completed.length,
    completedSales: money(completed.reduce((s, o) => s + o.total, 0)),
    uniqueCompletedBuyers: buyerSet(completed),
    reviews: top("productReviews").length,
    reports: top("reports").length,
    violations: top("violations").length,
    commodities: top("market_prices").length,
    priceHistory: docs.filter((d) => /^market_prices\/[^/]+\/history\/PHS/.test(d.path)).length,
    searchEvents: top("searchEvents").length,
    messages: docs.filter((d) => /^conversations\/[^/]+\/messages\//.test(d.path)).length,
    notifications: docs.filter((d) => /^notifications\/[^/]+\/items\//.test(d.path)).length,
    auditLogs: top("audit_logs").length,
    buyerDemandByArea: [...group(completed, areaOf)]
      .map(([area, list]) => ({ area, uniqueBuyers: buyerSet(list), completedOrders: list.length }))
      .sort((a, b) => b.uniqueBuyers - a.uniqueBuyers || b.completedOrders - a.completedOrders || a.area.localeCompare(b.area)),
    productDemandByCategory: [...group(completed, (o) => o.category)]
      .map(([category, list]) => ({ category, uniqueBuyers: buyerSet(list), completedOrders: list.length }))
      .sort((a, b) => b.uniqueBuyers - a.uniqueBuyers || a.category.localeCompare(b.category)),
    monthly,
  };
}

/**
 * The workbook's own summary sheets (KPI Summary, Buyer Demand By Area,
 * Product Demand By Category, Monthly Sales) against [summary]: one row
 * per figure, { check, workbook, computed, ok }. The summary sheets are
 * only compared, never imported.
 */
function crossCheck(sheets, summary, { notImported = [] } = {}) {
  const rows = [];
  const push = (check, workbook, computed) =>
    rows.push({ check, workbook, computed, ok: workbook === undefined ? null : Math.abs(Number(workbook) - Number(computed)) < 0.005 });
  const kpi = new Map(sheetRecords(sheets["KPI Summary"] || []).map((r) => [String(r.metric).trim(), r.value]));
  const pairs = [
    ["Buyers", "buyers"],
    ["Farmer applications", "farmers"],
    ["Approved farmers", "approvedFarmers"],
    ["Pending farmer verification", "pendingFarmers"],
    ["Rejected farmer verification", "rejectedFarmers"],
    ["Product listings", "listings"],
    ["Active product listings", "activeListings"],
    ["Completed orders", "completedOrders"],
    ["All orders", "allOrders"],
    ["Completed sales amount PHP", "completedSales"],
    ["Unique buyers with completed orders", "uniqueCompletedBuyers"],
    ["Reviews", "reviews"],
    ["User reports", "reports"],
    ["Violations/action records", "violations"],
    ["Commodity reference prices", "commodities"],
    ["Monthly price history records", "priceHistory"],
    ["Admin audit logs", "auditLogs"],
    ["Search events", "searchEvents"],
    ["Messages", "messages"],
    ["Notifications", "notifications"],
  ];
  for (const [metric, key] of pairs) {
    // A sheet left out on purpose is shown, not counted as a mismatch.
    if (notImported.includes(key)) rows.push({ check: `KPI · ${metric}`, workbook: kpi.get(metric), computed: "not imported", ok: null });
    else push(`KPI · ${metric}`, kpi.get(metric), summary[key]);
  }

  const areas = new Map(summary.buyerDemandByArea.map((a) => [a.area, a]));
  for (const r of sheetRecords(sheets["Buyer Demand By Area"] || [])) {
    const a = areas.get(String(r.location).trim()) || { uniqueBuyers: 0, completedOrders: 0 };
    push(`Buyer Demand · ${r.location} · unique buyers`, r.unique_completed_buyers, a.uniqueBuyers);
    push(`Buyer Demand · ${r.location} · completed orders`, r.completed_orders, a.completedOrders);
  }
  const categories = new Map(summary.productDemandByCategory.map((c) => [c.category, c]));
  for (const r of sheetRecords(sheets["Product Demand By Category"] || [])) {
    const name = CATEGORY_RENAMES[r.category] || r.category;
    const c = categories.get(name) || { uniqueBuyers: 0, completedOrders: 0 };
    const label = name === r.category ? name : `${r.category} (→ ${name})`;
    push(`Product Demand · ${label} · unique buyers`, r.unique_buyers, c.uniqueBuyers);
    push(`Product Demand · ${label} · completed orders`, r.completed_orders, c.completedOrders);
  }
  const seen = new Set();
  for (const r of sheetRecords(sheets["Monthly Sales"] || [])) {
    const month = String(r.month);
    const m = summary.monthly[month] || { allOrders: 0, completedOrders: 0, completedSales: 0 };
    const again = seen.has(month) ? " (repeated row)" : "";
    seen.add(month);
    push(`Monthly Sales · ${month}${again} · all orders (by date placed)`, r.all_orders, m.allOrders || 0);
    push(`Monthly Sales · ${month}${again} · completed orders (by date completed)`, r.completed_orders, m.completedOrders);
    push(`Monthly Sales · ${month}${again} · completed sales`, r.completed_sales_php, m.completedSales);
  }
  return rows;
}

module.exports = {
  BATCH_ID,
  SHEETS,
  CATEGORY_RENAMES,
  COMMODITY_RENAMES,
  sheetRecords,
  workbookRecords,
  manilaDate,
  manilaMonth,
  commodityDocId,
  splitName,
  formatStock,
  validateWorkbook,
  buildPlan,
  planCounts,
  summarize,
  crossCheck,
};
