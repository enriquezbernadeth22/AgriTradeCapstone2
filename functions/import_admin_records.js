#!/usr/bin/env node
// Imports AgriTrade_Admin_Records_Aug-Nov_2026.xlsx into Firestore: the
// workbook's users, farmer applications, commodities and reference
// prices, listings, orders, reviews, reports, violations, searches,
// chats and notifications, as the app itself stores them
// (import_admin_records_logic.js does the checking and mapping).
//
// Safe to run again: every document has a fixed id from the workbook and
// is created, never overwritten. A document that already exists is left
// exactly as it is and reported. Nothing outside the import is deleted.
//
//   node functions/import_admin_records.js <workbook.xlsx>              dry run (reads only)
//   node functions/import_admin_records.js <workbook.xlsx> --apply      writes
//   node functions/import_admin_records.js <workbook.xlsx> --verify     re-checks what is in Firestore
//   node functions/import_admin_records.js <workbook.xlsx> --remove     deletes only this import's documents
//
// Options:
//   --project <id>           Firebase project (default: the emulator's, or agritrade-bef87)
//   --confirm <id>           required with --apply / --remove outside the emulator: the project id again
//   --offline                dry run without reading Firestore (no credentials needed)
//   --include-audit-logs     also write the workbook's Audit Logs sheet to audit_logs
//   --report <file.md>       where to save the validation report (default: next to the workbook)
//   --plan-json <file.json>  also save every planned document as JSON
//   --photos <folder>        product photos, one per commodity ("corn.jpg"), with credits.json
//                            giving each one's title, author, license and source; uploaded to
//                            Firebase Storage (product-photos/imported/) before the documents
//   --photo-host <host>      where photos go: cloudinary (default; the app's own account and
//                            unsigned preset, as farmers' photos) or storage (Firebase Storage)
//   --bucket <name>          Storage bucket (default: <project>.firebasestorage.app)
//
// Credentials: on the emulator none (firebase emulators:exec sets
// FIRESTORE_EMULATOR_HOST). Otherwise Application Default Credentials:
// `gcloud auth application-default login`, or GOOGLE_APPLICATION_CREDENTIALS
// set to a service-account key of the project.
const fs = require("fs");
const path = require("path");
const { readWorkbook } = require("./xlsx_reader");
const logic = require("./import_admin_records_logic");

function parseArgs(argv) {
  const args = { flags: new Set(), values: {}, positional: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (["--project", "--confirm", "--report", "--plan-json", "--photos", "--bucket", "--photo-host"].includes(a)) args.values[a.slice(2)] = argv[++i];
    else if (a.startsWith("--")) args.flags.add(a.slice(2));
    else args.positional.push(a);
  }
  return args;
}

const chunk = (list, size) => {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
};

// Dates as {"$date": iso} so the JSON can be read back exactly.
const toJson = (value) =>
  JSON.stringify(value, (key, v) => (key !== "$date" && typeof v === "string" && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(v) ? { $date: v } : v), 1);

function table(rows) {
  const lines = ["| Check | Workbook | Computed | |", "|---|---:|---:|:-:|"];
  for (const r of rows) {
    const mark = r.ok === null ? "—" : r.ok ? "✓" : "✗";
    lines.push(`| ${r.check} | ${r.workbook ?? "—"} | ${r.computed} | ${mark} |`);
  }
  return lines.join("\n");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const file = args.positional[0];
  if (!file) {
    process.stderr.write("Usage: node functions/import_admin_records.js <workbook.xlsx> [--apply|--verify|--remove] [options]\n");
    process.exitCode = 2;
    return;
  }
  const mode = args.flags.has("remove") ? "remove" : args.flags.has("apply") ? "apply" : args.flags.has("verify") ? "verify" : "dry-run";
  const emulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  const projectId = args.values.project || process.env.GCLOUD_PROJECT || (emulator ? "demo-agritrade" : "agritrade-bef87");
  const offline = args.flags.has("offline");
  const includeAuditLogs = args.flags.has("include-audit-logs");
  if ((mode === "apply" || mode === "remove") && !emulator && args.values.confirm !== projectId) {
    process.stderr.write(
      `Refusing to ${mode} on project "${projectId}" (not the emulator) without --confirm ${projectId}.\n` +
        "Run a dry run first and read its report.\n"
    );
    process.exitCode = 2;
    return;
  }
  if (offline && mode !== "dry-run") {
    process.stderr.write("--offline is for a dry run only.\n");
    process.exitCode = 2;
    return;
  }

  const sheets = readWorkbook(file);
  const { errors, warnings } = logic.validateWorkbook(sheets);
  const report = [];
  const say = (line = "") => {
    report.push(line);
    process.stdout.write(line + "\n");
  };
  say(`# AgriTrade+ records import — ${mode}`);
  say();
  say(`- Workbook: ${path.basename(file)}`);
  say(`- Target: ${offline ? "(offline, Firestore not read)" : `${projectId}${emulator ? ` (emulator ${process.env.FIRESTORE_EMULATOR_HOST})` : ""}`}`);
  say(`- Import batch: \`${logic.BATCH_ID}\` (on every document as importBatch)`);
  say(`- Run at: ${new Date().toISOString()}`);
  say();
  say(`## Validation: ${errors.length} error(s), ${warnings.length} warning(s)`);
  for (const e of errors) say(`- ERROR ${e}`);
  for (const w of warnings) say(`- warning ${w}`);
  if (errors.length) {
    say();
    say("Nothing was written: fix the errors in the workbook and run again.");
    process.exitCode = 1;
    return saveReport(args, file, report);
  }

  const bucket = args.values.bucket || `${projectId}.firebasestorage.app`;
  const { photos, problems } = args.values.photos ? readPhotos(args.values.photos, bucket) : { photos: {}, problems: [] };
  const photoHost = args.values["photo-host"] || "cloudinary";
  if (!["cloudinary", "storage"].includes(photoHost)) throw new Error(`--photo-host must be cloudinary or storage, not "${photoHost}".`);
  if (photoHost === "cloudinary" && Object.keys(photos).length) {
    await cloudinaryPhotos(photos, args.values.photos, { upload: mode === "apply" && !emulator });
  }
  const photoUrls = Object.fromEntries(Object.entries(photos).map(([slug, p]) => [slug, p.url]));
  const plan = logic.buildPlan(sheets, { includeAuditLogs, photoUrls });
  if (args.values["plan-json"]) fs.writeFileSync(args.values["plan-json"], toJson(plan));
  say();
  say(`## Planned documents: ${plan.length}`);
  for (const [key, n] of Object.entries(logic.planCounts(plan))) say(`- ${key}: ${n}`);
  if (!includeAuditLogs) say("- audit_logs: 0 (left out; add --include-audit-logs to write the workbook's admin activity)");
  const commodities = plan.filter((d) => /^market_prices\/[^/]+$/.test(d.path)).map((d) => d.path.split("/")[1]);
  say();
  say(`## Product photos: ${Object.keys(photos).length} of ${commodities.length} commodities`);
  if (!args.values.photos) say("- none given (--photos <folder>): the listings show the app's no-photo placeholder.");
  for (const [slug, p] of Object.entries(photos)) {
    say(`- ${slug}: "${p.credit.title || path.basename(p.file)}" by ${p.credit.author || "unknown"}, ${p.credit.license} (${p.credit.source})`);
  }
  for (const problem of problems) say(`- not used: ${problem}`);
  const without = commodities.filter((slug) => !photos[slug]);
  if (args.values.photos && without.length) say(`- no photo: ${without.join(", ")}`);

  let db = null;
  if (!offline) {
    const { initializeApp, getApps } = require("firebase-admin/app");
    const { getFirestore } = require("firebase-admin/firestore");
    if (!getApps().length) initializeApp({ projectId });
    db = getFirestore();
  }

  // What is there already: ours from an earlier run, or someone else's.
  const existing = new Map();
  if (db) {
    for (const part of chunk(plan, 300)) {
      const snaps = await db.getAll(...part.map((d) => db.doc(d.path)));
      snaps.forEach((snap, i) => {
        if (snap.exists) existing.set(part[i].path, snap.data().importBatch === logic.BATCH_ID ? "ours" : "other");
      });
    }
    const ours = [...existing.values()].filter((v) => v === "ours").length;
    const other = existing.size - ours;
    say();
    say(`## Already in Firestore: ${existing.size}`);
    say(`- from this import (left as they are): ${ours}`);
    say(`- not from this import (never overwritten, skipped): ${other}`);
    for (const [p, v] of existing) if (v === "other") say(`  - ${p}`);
  }

  // A reference price added under a commodity the project already has in
  // another unit would put two units on one price trend: left out.
  const unitClash = new Set();
  if (db) {
    for (const d of plan.filter((x) => /^market_prices\/[^/]+$/.test(x.path) && existing.get(x.path) === "other")) {
      const snap = await db.doc(d.path).get();
      const unit = String(snap.data().unit || "kg");
      if (unit !== d.data.unit) {
        for (const h of plan) if (h.path.startsWith(`${d.path}/history/`)) unitClash.add(h.path);
        say(`- ${d.path} is priced per "${unit}" here and per "${d.data.unit}" in the workbook: its ${[...unitClash].filter((p) => p.startsWith(d.path)).length} dated prices are left out.`);
      }
    }
  }

  if (mode === "remove") return remove(db, plan, say, args, file, report);

  if (mode === "apply" && Object.keys(photos).length) {
    // Photos first: a listing never points at a photo that is not there.
    say();
    if (photoHost === "cloudinary") {
      say(`## Photos: on Cloudinary (${Object.values(photos).filter((p) => p.uploadedNow).length} uploaded now, the rest from an earlier run)`);
    } else if (emulator && !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
      say("## Photos: not uploaded (no Storage emulator running); their addresses are still on the documents.");
    } else {
      const { getStorage } = require("firebase-admin/storage");
      const store = getStorage().bucket(bucket);
      say(`## Uploading ${Object.keys(photos).length} photo(s) to ${bucket}`);
      for (const [slug, p] of Object.entries(photos)) {
        const target = store.file(p.storagePath);
        const [there] = await target.exists();
        if (there) {
          const [meta] = await target.getMetadata();
          if ((meta.metadata || {}).firebaseStorageDownloadTokens === p.token) continue;
        }
        await target.save(p.bytes, {
          contentType: p.contentType,
          resumable: false,
          metadata: {
            cacheControl: "public, max-age=31536000",
            metadata: {
              firebaseStorageDownloadTokens: p.token,
              title: String(p.credit.title || ""),
              author: String(p.credit.author || ""),
              license: String(p.credit.license),
              source: String(p.credit.source),
            },
          },
        });
        say(`- ${slug}`);
      }
    }
    // This import's own listings, orders and chats from an earlier run
    // get the photo too: only their photo fields change.
    let updated = 0;
    const writer = db.bulkWriter();
    for (const d of plan) {
      if (existing.get(d.path) !== "ours") continue;
      const fields = ["imageUrl", "imageUrls", "productImageUrl"].filter((k) => k in d.data && d.data[k] !== "" && !(Array.isArray(d.data[k]) && !d.data[k].length));
      if (!fields.length) continue;
      writer.update(db.doc(d.path), Object.fromEntries(fields.map((k) => [k, d.data[k]])));
      updated++;
    }
    await writer.close();
    if (updated) say(`- photo added to ${updated} document(s) imported earlier`);
  }

  if (mode === "apply") {
    const toWrite = plan.filter((d) => !existing.has(d.path) && !unitClash.has(d.path));
    say();
    say(`## Writing ${toWrite.length} document(s)`);
    let written = 0;
    const failed = [];
    // In dependency order, one collection group at a time, so every
    // trigger finds what it reads (a listing before its orders).
    const groups = [];
    for (const d of toWrite) {
      const key = logic.planCounts([d]);
      const name = Object.keys(key)[0];
      if (!groups.length || groups[groups.length - 1].name !== name) groups.push({ name, docs: [] });
      groups[groups.length - 1].docs.push(d);
    }
    for (const group of groups) {
      const writer = db.bulkWriter();
      writer.onWriteError((error) => {
        // ALREADY_EXISTS: created meanwhile by someone else; left alone.
        if (error.code === 6) return false;
        return error.failedAttempts < 3;
      });
      for (const d of group.docs) {
        writer
          .create(db.doc(d.path), d.data)
          .then(() => written++)
          .catch((e) => failed.push(`${d.path}: ${e.code === 6 ? "already exists, left as it is" : e.message}`));
      }
      await writer.close();
      say(`- ${group.name}: ${group.docs.length}`);
    }
    say(`- written: ${written}; not written: ${failed.length}`);
    for (const f of failed) say(`  - ${f}`);
    if (failed.length) process.exitCode = 1;
  }

  // The cross-check: the workbook's summary sheets against the numbers of
  // the imported documents (the plan on a dry run, what Firestore holds
  // after writing or on --verify).
  let docs = plan;
  let source = "the planned documents";
  if (db && mode !== "dry-run") {
    docs = [];
    for (const part of chunk(plan, 300)) {
      const snaps = await db.getAll(...part.map((d) => db.doc(d.path)));
      snaps.forEach((snap, i) => {
        if (snap.exists && snap.data().importBatch === logic.BATCH_ID) docs.push({ path: part[i].path, data: snap.data() });
      });
    }
    source = `the ${docs.length} imported documents read back from Firestore`;
    say();
    say(`## In Firestore from this import: ${docs.length} of ${plan.length} planned`);
  }
  const summary = logic.summarize(docs);
  const checks = logic.crossCheck(sheets, summary, { notImported: includeAuditLogs ? [] : ["auditLogs"] });
  const bad = checks.filter((c) => c.ok === false);
  say();
  say(`## Cross-check against the workbook's summary sheets (from ${source})`);
  say(`${checks.filter((c) => c.ok).length} of ${checks.filter((c) => c.ok !== null).length} match.`);
  if (bad.length) {
    say();
    say("Not matching:");
    say(table(bad));
  }
  say();
  say("<details><summary>Every check</summary>");
  say();
  say(table(checks));
  say();
  say("</details>");
  say();
  say("## How the workbook was mapped");
  say("- Admin rows (ADM…) are not imported as accounts; their names are kept where they reviewed or acted.");
  say("- No sign-in (Firebase Auth) accounts are created: the imported buyers and farmers are records, not logins.");
  say("- Account status Inactive and Unverified → active (the app has no such state); a farmer's state is their application's.");
  say("- Category Others → Fruits (Coconut, Banana: the app's own category). Chicken (Liveweight) → Chicken (per kg).");
  say("- Listings: wholesale_enabled is kept off (the workbook has no wholesale price or minimum); no description (none given); photos only from --photos.");
  say("- Delivery coverage: Selected areas = every town a workbook buyer is in (Laurel, Malvar, Balete, Tanauan City, Lumban); fee to be arranged.");
  say("- Reference prices: marked \"Internal reference price (not DA-issued)\" and isTestData; Price Changes become dated history entries.");
  say("- Conversations between the same buyer and farmer are one thread (the app's id: both ids sorted); one with no messages is left out.");
  say("- Search events carry buyerId, not userId, so Trending Searches (counted on the day they arrive) are not filled with past searches.");
  say("- Every document has importBatch and importSourceId; --remove deletes exactly those.");
  if (mode === "dry-run") {
    say();
    say(errors.length ? "" : "Dry run only: nothing was written. Run again with --apply to write.");
  }
  saveReport(args, file, report);
}

async function remove(db, plan, say, args, file, report) {
  // Ours only: a document is deleted when it carries this import's batch.
  // A commodity record is kept while a listing not from this import still
  // uses it (removing it would hide that farmer's listing).
  const ours = [];
  for (const part of chunk(plan, 300)) {
    const snaps = await db.getAll(...part.map((d) => db.doc(d.path)));
    snaps.forEach((snap, i) => {
      if (snap.exists && snap.data().importBatch === logic.BATCH_ID) ours.push(part[i].path);
    });
  }
  const kept = [];
  for (const p of ours.filter((x) => /^market_prices\/[^/]+$/.test(x))) {
    const name = (await db.doc(p).get()).data().name;
    const used = await db.collection("products").where("commodity", "==", name).get();
    if (used.docs.some((d) => d.data().importBatch !== logic.BATCH_ID)) kept.push(p);
  }
  // The notifications the server made for imported accounts while
  // importing (welcome, new order, new message) go with those accounts.
  const extra = [];
  for (const uid of ours.filter((p) => /^users\/[^/]+$/.test(p)).map((p) => p.split("/")[1])) {
    const items = await db.collection(`notifications/${uid}/items`).get();
    for (const d of items.docs) extra.push(d.ref.path);
  }
  for (const p of ours.filter((x) => /^orders\/[^/]+$/.test(x))) {
    const id = p.split("/")[1];
    for (const side of ["buyer", "farmer"]) {
      const snap = await db.doc(`orders/${id}/private/${side}`).get();
      if (snap.exists) extra.push(snap.ref.path);
    }
    const sale = await db.doc(`market_sales/${id}`).get();
    if (sale.exists) extra.push(sale.ref.path);
  }
  const targets = [...new Set([...extra, ...ours.filter((p) => !kept.includes(p)).reverse()])];
  say();
  say(`## Removing ${targets.length} document(s) of this import`);
  for (const k of kept) say(`- kept ${k}: a listing not from this import uses it`);
  const writer = db.bulkWriter();
  for (const p of targets) writer.delete(db.doc(p));
  await writer.close();
  say(`- removed: ${targets.length}`);
  saveReport(args, file, report);
}

// The product photos in [dir] (--photos): one per commodity, named by its
// record id ("corn.jpg", "sweet_potato.webp"), each with its source and
// licence in dir/credits.json ({ "corn": { "title", "author", "license",
// "source" } }). A photo without a credit is refused: only photos whose
// licence is known are used. Each gets a fixed Storage path and download
// token, so a second run gives the same address.
function readPhotos(dir, bucket) {
  const crypto = require("crypto");
  const creditsFile = path.join(dir, "credits.json");
  const credits = fs.existsSync(creditsFile) ? JSON.parse(fs.readFileSync(creditsFile, "utf8")) : {};
  const types = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp" };
  const photos = {};
  const problems = [];
  for (const name of fs.readdirSync(dir)) {
    const m = /^([a-z0-9_]+)\.(jpe?g|png|webp)$/i.exec(name);
    if (!m) continue;
    const slug = m[1].toLowerCase();
    const credit = credits[slug];
    if (!credit || !credit.license || !credit.source) {
      problems.push(`${name}: no licence and source in credits.json, so it is not used.`);
      continue;
    }
    const bytes = fs.readFileSync(path.join(dir, name));
    const hash = crypto.createHash("sha1").update(bytes).digest("hex");
    const token = `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-a${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
    const storagePath = `product-photos/imported/${slug}.${m[2].toLowerCase()}`;
    photos[slug] = {
      file: path.join(dir, name),
      bytes,
      contentType: types[m[2].toLowerCase()],
      storagePath,
      token,
      hash,
      credit,
      url: `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`,
    };
  }
  return { photos, problems };
}

// The app's own Cloudinary account and unsigned preset (CloudinaryService),
// where every listing photo already lives. Cloudinary names an upload
// itself, so the addresses are kept in dir/cloudinary_urls.json by the
// photo's content: a later run reuses them instead of uploading again.
// Without [upload] (a dry run, or the emulator) nothing goes up, and a
// photo not uploaded yet shows a stand-in address.
const CLOUDINARY = { cloud: "gxir71bo", preset: "agritrade_unsigned", folder: "agritrade/imported" };
async function cloudinaryPhotos(photos, dir, { upload }) {
  const cacheFile = path.join(dir, "cloudinary_urls.json");
  const cache = fs.existsSync(cacheFile) ? JSON.parse(fs.readFileSync(cacheFile, "utf8")) : {};
  for (const [slug, p] of Object.entries(photos)) {
    const known = cache[slug];
    if (known && known.sha1 === p.hash) {
      p.url = known.url;
      continue;
    }
    if (!upload) {
      p.url = `(uploaded to Cloudinary on --apply: ${slug})`;
      continue;
    }
    const form = new FormData();
    form.append("file", new Blob([p.bytes], { type: p.contentType }), path.basename(p.file));
    form.append("upload_preset", CLOUDINARY.preset);
    form.append("folder", CLOUDINARY.folder);
    const res = await fetch(`https://api.cloudinary.com/v1_1/${CLOUDINARY.cloud}/image/upload`, { method: "POST", body: form });
    const body = await res.json();
    if (!res.ok || !body.secure_url) throw new Error(`Cloudinary refused ${slug}: ${(body.error && body.error.message) || res.status}`);
    p.url = body.secure_url;
    p.uploadedNow = true;
    cache[slug] = { sha1: p.hash, url: body.secure_url, publicId: body.public_id };
    // Saved after each one, so a failure part-way loses nothing.
    fs.writeFileSync(cacheFile, JSON.stringify(cache, null, 2));
  }
}

function saveReport(args, file, report) {
  const out = args.values.report || path.join(path.dirname(file), "AgriTrade_import_report.md");
  fs.writeFileSync(out, report.join("\n") + "\n");
  process.stdout.write(`\nReport saved: ${out}\n`);
}

main().catch((error) => {
  if (/default credentials/i.test(String(error && error.message))) {
    process.stderr.write(
      "\nNo Firebase credentials. In PowerShell, point to the project's service-account key first:\n" +
        '  $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\\Users\\<you>\\Downloads\\<project>-firebase-adminsdk-....json"\n' +
        "(Git Bash: export GOOGLE_APPLICATION_CREDENTIALS=...). Or add --offline for a dry run without Firestore.\n"
    );
    process.exitCode = 1;
    return;
  }
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
