/**
 * Renders a sample agreement from the generated templates, using the same
 * token substitution + uncompressed-zip packing the browser does. Useful to
 * eyeball the output in Word without going through the portal.
 *
 * Run: node scripts/preview-agreement.mjs ballari
 */
import { readFileSync, writeFileSync } from 'node:fs';

const branch = process.argv[2] ?? 'ballari';
const template = JSON.parse(readFileSync(`public/templates/agreement-${branch}.json`, 'utf8'));

const SAMPLE = {
  DATE_DAY: '17',
  DATE_DAY_SUFFIX: 'th',
  DATE_MONTH: 'September',
  DATE_YEAR: '2026',
  DATE_DMY: '17-09-2026',
  CUSTOMER_NAME: 'Ramesh Kumar & Sons',
  CUSTOMER_ADDRESS: 'No 24, 2nd Cross, Gandhi Nagar, Ballari-583101, Karnataka',
  CUSTOMER_AADHAAR: '2239 8411 1913',
  CUSTOMER_PAN: 'ALDPK7468C',
  CUSTOMER_EMAIL: 'ramesh.kumar@example.com',
  CUSTOMER_PHONE: '9591999535',
  AMOUNT: '7,25,000',
  AMOUNT_WORDS: 'Seven Lakhs Twenty Five Thousand',
  INTEREST_RATE: '5%',
  TDS_RATE: '10%',
  PERIOD_FROM: '17.09.2026',
  PERIOD_TO: '16.09.2027',
  CHEQUE_NO: '143538',
  CHEQUE_BANK_NAME: 'SBI Bank',
  CHEQUE_BANK_ADDRESS: 'Gunj Circle, Raichur Branch',
  BANK_HOLDER: 'Ramesh Kumar',
  BANK_ACCOUNT: '20051099782',
  BANK_IFSC: 'SBIN0000817',
  BANK_NAME: 'SBI Bank',
  BANK_BRANCH: 'Main Branch, Ballari',
  NOMINEE_NAME: 'Saroja Kumar',
  NOMINEE_AADHAAR: '4515 8735 2354',
  NOMINEE_PAN: 'TSHPS6801M',
  NOMINEE_RELATION: 'Wife',
  NOMINEE_PHONE: '8904307413',
};

function escapeXml(value) {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i += 1) {
    let value = i;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[i] = value >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) {
    crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildDocx(parts) {
  const encoder = new TextEncoder();
  const entries = parts.map((part) => {
    const name = encoder.encode(part.path);
    const data = encoder.encode(part.text);
    return { name, data, crc: crc32(data) };
  });

  const localSize = entries.reduce((t, e) => t + 30 + e.name.length + e.data.length, 0);
  const centralSize = entries.reduce((t, e) => t + 46 + e.name.length, 0);
  const buffer = new Uint8Array(localSize + centralSize + 22);
  const view = new DataView(buffer.buffer);

  let offset = 0;
  const offsets = [];

  for (const entry of entries) {
    offsets.push(offset);
    view.setUint32(offset, 0x04034b50, true);
    view.setUint16(offset + 4, 20, true);
    view.setUint16(offset + 6, 0x0800, true);
    view.setUint16(offset + 8, 0, true);
    view.setUint16(offset + 10, 0, true);
    view.setUint16(offset + 12, 0x5921, true);
    view.setUint32(offset + 14, entry.crc, true);
    view.setUint32(offset + 18, entry.data.length, true);
    view.setUint32(offset + 22, entry.data.length, true);
    view.setUint16(offset + 26, entry.name.length, true);
    view.setUint16(offset + 28, 0, true);
    buffer.set(entry.name, offset + 30);
    buffer.set(entry.data, offset + 30 + entry.name.length);
    offset += 30 + entry.name.length + entry.data.length;
  }

  const centralStart = offset;

  entries.forEach((entry, index) => {
    view.setUint32(offset, 0x02014b50, true);
    view.setUint16(offset + 4, 20, true);
    view.setUint16(offset + 6, 20, true);
    view.setUint16(offset + 8, 0x0800, true);
    view.setUint16(offset + 10, 0, true);
    view.setUint16(offset + 12, 0, true);
    view.setUint16(offset + 14, 0x5921, true);
    view.setUint32(offset + 16, entry.crc, true);
    view.setUint32(offset + 20, entry.data.length, true);
    view.setUint32(offset + 24, entry.data.length, true);
    view.setUint16(offset + 28, entry.name.length, true);
    view.setUint16(offset + 30, 0, true);
    view.setUint16(offset + 32, 0, true);
    view.setUint16(offset + 34, 0, true);
    view.setUint16(offset + 36, 0, true);
    view.setUint32(offset + 38, 0, true);
    view.setUint32(offset + 42, offsets[index], true);
    buffer.set(entry.name, offset + 46);
    offset += 46 + entry.name.length;
  });

  view.setUint32(offset, 0x06054b50, true);
  view.setUint16(offset + 4, 0, true);
  view.setUint16(offset + 6, 0, true);
  view.setUint16(offset + 8, entries.length, true);
  view.setUint16(offset + 10, entries.length, true);
  view.setUint32(offset + 12, offset - centralStart, true);
  view.setUint32(offset + 16, centralStart, true);
  view.setUint16(offset + 20, 0, true);

  return buffer;
}

const leftover = new Set();
const filled = template.parts.map((part) => {
  if (part.path !== 'word/document.xml') {
    return part;
  }
  const text = part.text.replace(/\{\{([A-Z_]+)\}\}/g, (match, token) => {
    if (token in SAMPLE) {
      return escapeXml(SAMPLE[token]);
    }
    leftover.add(token);
    return match;
  });
  return { path: part.path, text };
});

const out = `preview-agreement-${branch}.docx`;
writeFileSync(out, buildDocx(filled));
console.log(`wrote ${out}`);
if (leftover.size > 0) {
  console.log(`UNFILLED TOKENS: ${[...leftover].join(', ')}`);
}
