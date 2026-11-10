/**
 * A small .xlsx reader for the admin-records import
 * (import_admin_records.js): every sheet of a workbook as rows of cell
 * values, with no extra dependency. It reads the zip's central directory,
 * inflates the parts it needs with Node's zlib, and takes cell values from
 * the sheet XML: shared strings, inline strings, numbers and booleans.
 * Formulas give their cached value. Styles, dates stored as serial numbers
 * and charts are not interpreted; the workbook keeps its dates as text.
 */
const fs = require("fs");
const zlib = require("zlib");

/** The files inside a zip archive, by name, as Buffers. */
function unzip(buffer) {
  // The end-of-central-directory record is in the last 64 KiB + 22 bytes.
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65558); i--) {
    if (buffer.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("Not a zip file (no end of central directory).");
  const entries = buffer.readUInt16LE(eocd + 10);
  let offset = buffer.readUInt32LE(eocd + 16);
  const files = {};
  for (let n = 0; n < entries; n++) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) throw new Error("Corrupt zip central directory.");
    const method = buffer.readUInt16LE(offset + 10);
    const compressedSize = buffer.readUInt32LE(offset + 20);
    const nameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const localOffset = buffer.readUInt32LE(offset + 42);
    const name = buffer.toString("utf8", offset + 46, offset + 46 + nameLength);
    const localNameLength = buffer.readUInt16LE(localOffset + 26);
    const localExtraLength = buffer.readUInt16LE(localOffset + 28);
    const start = localOffset + 30 + localNameLength + localExtraLength;
    const raw = buffer.subarray(start, start + compressedSize);
    if (method === 0) files[name] = raw;
    else if (method === 8) files[name] = zlib.inflateRawSync(raw);
    else throw new Error(`Unsupported zip compression method ${method} for ${name}.`);
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return files;
}

function unescapeXml(s) {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&amp;/g, "&");
}

// The text runs (<t>) of a shared or inline string, joined.
function textOf(xml) {
  return unescapeXml(
    [...xml.matchAll(/<(?:\w+:)?t(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?t>/g)].map((m) => m[1]).join("")
  );
}

/** "AB12" -> 27 (zero-based column index). */
function columnIndex(ref) {
  const letters = /^[A-Z]+/.exec(ref)[0];
  let n = 0;
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/** The cell values of one sheet's XML, row by row. */
function parseSheet(xml, shared) {
  const rows = [];
  for (const row of xml.matchAll(/<(?:\w+:)?row\b[^>]*?(?:\/>|>([\s\S]*?)<\/(?:\w+:)?row>)/g)) {
    const cells = [];
    for (const cell of (row[1] || "").matchAll(/<(?:\w+:)?c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/g)) {
      const attrs = cell[1];
      const body = cell[2] || "";
      const ref = /\br="([A-Z]+)\d+"/.exec(attrs);
      const type = (/\bt="([^"]+)"/.exec(attrs) || [])[1];
      const v = /<(?:\w+:)?v>([\s\S]*?)<\/(?:\w+:)?v>/.exec(body);
      let value = null;
      if (type === "s" && v) value = shared[+v[1]] ?? null;
      else if (type === "inlineStr") value = textOf(body);
      else if (type === "str" && v) value = unescapeXml(v[1]);
      else if (type === "b" && v) value = v[1] === "1";
      else if (type === "e") value = null;
      else if (v) value = v[1] !== "" && !isNaN(+v[1]) ? +v[1] : unescapeXml(v[1]);
      cells[ref ? columnIndex(ref[1]) : cells.length] = value;
    }
    // Holes left by empty cells read as null.
    rows.push(Array.from(cells, (c) => (c === undefined ? null : c)));
  }
  return rows;
}

/** { sheetName: rows } for the workbook at [path] (or a Buffer). */
function readWorkbook(pathOrBuffer) {
  const buffer = Buffer.isBuffer(pathOrBuffer) ? pathOrBuffer : fs.readFileSync(pathOrBuffer);
  const files = unzip(buffer);
  const text = (name) => {
    const file = files[name] || files["/" + name];
    return file ? file.toString("utf8") : null;
  };
  const sharedXml = text("xl/sharedStrings.xml");
  const shared = sharedXml
    ? [...sharedXml.matchAll(/<(?:\w+:)?si>([\s\S]*?)<\/(?:\w+:)?si>/g)].map((m) => textOf(m[1]))
    : [];
  const workbook = text("xl/workbook.xml");
  const rels = text("xl/_rels/workbook.xml.rels");
  if (!workbook || !rels) throw new Error("Not an .xlsx workbook (xl/workbook.xml missing).");
  const targets = {};
  for (const rel of rels.matchAll(/<(?:\w+:)?Relationship\s[^>]*>/g)) {
    const id = /\bId="([^"]+)"/.exec(rel[0]);
    const target = /\bTarget="([^"]+)"/.exec(rel[0]);
    if (id && target) targets[id[1]] = target[1].replace(/^\/?(xl\/)?/, "xl/");
  }
  const sheets = {};
  for (const sheet of workbook.matchAll(/<(?:\w+:)?sheet\s[^>]*>/g)) {
    const name = unescapeXml(/\bname="([^"]+)"/.exec(sheet[0])[1]);
    const rid = /\br:id="([^"]+)"/.exec(sheet[0])[1];
    const xml = text(targets[rid]);
    sheets[name] = xml ? parseSheet(xml, shared) : [];
  }
  return sheets;
}

module.exports = { readWorkbook, parseSheet, unzip, columnIndex };
