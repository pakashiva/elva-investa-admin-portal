/**
 * Turns the two source loan agreements into token templates for the portal.
 *
 * Source: scripts/agreement-sources/extracted/<branch>/**   (unzipped .docx)
 * Output: public/templates/agreement-<branch>.json
 *
 * Only the paragraphs that contain customer/investment specific text are
 * rewritten; every other part of the document is copied byte for byte, so the
 * generated file keeps the original fonts, spacing, numbering and layout.
 * Each rewritten paragraph keeps its <w:pPr> and re-creates the runs with the
 * same bold / underline / superscript emphasis the original had.
 *
 * Run: node scripts/build-agreement-templates.mjs
 */
import { readdirSync, readFileSync, mkdirSync, writeFileSync, statSync } from 'node:fs';
import { join, posix } from 'node:path';

const SOURCE_ROOT = 'scripts/agreement-sources/extracted';
const OUTPUT_DIR = 'public/templates';

/** Parts are written in this order; [Content_Types].xml must come first. */
function collectParts(root) {
  const files = [];
  (function walk(dir, prefix) {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const rel = prefix ? posix.join(prefix, entry) : entry;
      if (statSync(full).isDirectory()) {
        walk(full, rel);
      } else {
        files.push({ path: rel, text: readFileSync(full, 'utf8') });
      }
    }
  })(root, '');

  return files.sort((a, b) => {
    if (a.path === '[Content_Types].xml') return -1;
    if (b.path === '[Content_Types].xml') return 1;
    return a.path.localeCompare(b.path);
  });
}

const RS_QUOTE_OPEN = '\u201c';
const RS_QUOTE_CLOSE = '\u201d';
const APOSTROPHE = '\u2019';

const firstPartyIdentity = {
  t: 'Aadhaar No: {{CUSTOMER_AADHAAR}}, PAN No: {{CUSTOMER_PAN}}, Email: {{CUSTOMER_EMAIL}}, Ph no: {{CUSTOMER_PHONE}}.',
  b: true,
};

const amountParagraph = [
  { t: 'Whereas the First party has provided a sum of ' },
  { t: 'RS. {{AMOUNT}}/- (Rupees {{AMOUNT_WORDS}} only) ', b: true },
  { t: 'by way of ' },
  { t: 'NEFT', b: true },
  {
    t: ' to the second party before the following witnesses. Thus the second party has received the amount and acknowledges the receipt of the same, as loan.',
  },
];

const interestParagraph = [
  {
    t: 'Whereas the second party will agreed to pay monthly interest on total loan of ',
  },
  { t: '{{INTEREST_RATE}}', b: true },
  {
    t: ' to the first party as per Section 194A deals with the provisions relating to TDS on interest other than on securities. Tax is to be deducted under section 194A, If interest (other than interest on securities) is paid to a resident.',
  },
];

const tdsParagraph = [
  {
    t: `Whereas the second party will deduct TDS @ {{TDS_RATE}} on first party${APOSTROPHE}s monthly returns on loan and the form-16 will be submitted every 6 months through Email.`,
  },
];

const periodParagraph = [
  { t: 'Whereas this agreement Period will be for ' },
  { t: '1 (one) Year', b: true },
  { t: ' commencing from ' },
  { t: '{{PERIOD_FROM}}', b: true, u: true },
  { t: ' to ', b: true },
  { t: '{{PERIOD_TO}}', b: true },
  {
    t: ' and after this agreement period both the parties can renewal with mutual understanding.',
  },
];

const nomineeTail =
  'Aadhar Card No: {{NOMINEE_AADHAAR}}, Pan no: {{NOMINEE_PAN}}, Relation: {{NOMINEE_RELATION}}, Ph.no: {{NOMINEE_PHONE}}.';

/**
 * Each rule finds exactly one paragraph by `match` and replaces its runs.
 * The build fails loudly if a rule matches zero or multiple paragraphs, so a
 * template edit can never silently drop a variable.
 */
const RULES = {
  ballari: [
    {
      match: 'is made an executed at Ballari',
      segments: [
        { t: 'This agreement of Loan is made an executed at Ballari on this ' },
        { t: '{{DATE_DAY}}' },
        { t: '{{DATE_DAY_SUFFIX}}', sup: true },
        { t: ' day of {{DATE_MONTH}} {{DATE_YEAR}}' },
      ],
    },
    {
      match: ') by and between: -',
      segments: [{ t: ' ({{DATE_DMY}}) by and between: -' }],
    },
    {
      match: 'permanent address',
      segments: [
        { t: '{{CUSTOMER_NAME}}, permanent address', b: true },
        { t: ': {{CUSTOMER_ADDRESS}}. ' },
        firstPartyIdentity,
        { t: ' Herein after called the ' },
        { t: 'FIRST PARTY / ', b: true },
        { t: 'of the ' },
        { t: 'ONE PART.', b: true },
        { t: ' ' },
      ],
    },
    { match: 'has provided a sum of', segments: amountParagraph },
    { match: 'agreed to pay monthly interest', segments: interestParagraph },
    { match: 'will deduct TDS @', segments: tdsParagraph },
    { match: 'commencing from', segments: periodParagraph },
    {
      match: 'Cheque bearing',
      segments: [
        { t: 'The second party has issued a Cheque bearing No ' },
        { t: `${RS_QUOTE_OPEN}{{CHEQUE_NO}}${RS_QUOTE_CLOSE}`, b: true },
        {
          t: ' {{CHEQUE_BANK_NAME}}, {{CHEQUE_BANK_ADDRESS}} to the First party for surety purpose.',
        },
      ],
    },
    {
      match: 'First Party Account Details',
      segments: [
        { t: 'First Party Account Details: Name: ' },
        { t: '{{BANK_HOLDER}}, ', b: true },
        {
          t: 'A/c No: {{BANK_ACCOUNT}}, IFSC: {{BANK_IFSC}}, Bank: {{BANK_NAME}}, Branch: {{BANK_BRANCH}}.',
        },
      ],
    },
    {
      match: 'First party Nominee',
      segments: [
        { t: 'First party Nominee Details: - Name: ' },
        { t: '{{NOMINEE_NAME}}, ', b: true },
        { t: nomineeTail },
      ],
    },
  ],
  raichur: [
    {
      match: 'is made an executed at ',
      segments: [
        { t: 'This agreement of Loan is made an executed at Raichur on this ' },
        { t: '{{DATE_DAY}}' },
        { t: '{{DATE_DAY_SUFFIX}}', sup: true },
        { t: ' Day of {{DATE_MONTH}} {{DATE_YEAR}}' },
      ],
    },
    {
      match: ') by and between: -',
      segments: [{ t: ' ({{DATE_DMY}}) by and between: -' }],
    },
    {
      match: 'permanent address',
      segments: [
        { t: '{{CUSTOMER_NAME}}, permanent address', b: true },
        { t: ': {{CUSTOMER_ADDRESS}}. ' },
        firstPartyIdentity,
        { t: ' Herein after called the ' },
        { t: 'FIRST PARTY.', b: true },
        { t: ' ' },
      ],
    },
    { match: 'has provided a sum of', segments: amountParagraph },
    { match: 'agreed to pay monthly interest', segments: interestParagraph },
    { match: 'will deduct TDS @', segments: tdsParagraph },
    { match: 'commencing from', segments: periodParagraph },
    {
      match: 'Cheque bearing',
      segments: [
        { t: `The second party has issued a Cheque bearing No ${RS_QUOTE_OPEN}` },
        { t: `{{CHEQUE_NO}}${RS_QUOTE_CLOSE} `, b: true },
        {
          t: '{{CHEQUE_BANK_NAME}}, {{CHEQUE_BANK_ADDRESS}} to the First party for surety purpose.',
        },
      ],
    },
    {
      match: 'First Party Account Details',
      segments: [
        { t: 'First Party Account Details: Name: ' },
        { t: '{{BANK_HOLDER}}, ', b: true },
        {
          t: 'A/c No: {{BANK_ACCOUNT}}, IFSC: {{BANK_IFSC}}, Bank: {{BANK_NAME}}, Branch: {{BANK_BRANCH}}, Ph.no: {{CUSTOMER_PHONE}}.',
        },
      ],
    },
    {
      match: 'First party Nominee',
      segments: [
        { t: 'First party Nominee Details: Name: ' },
        { t: '{{NOMINEE_NAME}}, ', b: true },
        { t: nomineeTail },
      ],
    },
  ],
};

function escapeXml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function paragraphText(paragraph) {
  return (paragraph.match(/<w:t[^>]*>[\s\S]*?<\/w:t>/g) ?? [])
    .map((t) => t.replace(/<[^>]+>/g, ''))
    .join('');
}

/** Font + size of the paragraph, so rebuilt runs inherit the same typography. */
function baseRunProps(paragraph) {
  const fonts = paragraph.match(/<w:rFonts[^>]*\/>/);
  const sz = paragraph.match(/<w:sz w:val="\d+"\/>/);
  const szCs = paragraph.match(/<w:szCs w:val="\d+"\/>/);
  return {
    fonts: fonts ? fonts[0] : '',
    sz: sz ? sz[0] : '',
    szCs: szCs ? szCs[0] : '',
  };
}

/** OOXML requires rPr children in schema order: rFonts, b, u, sz, szCs, vertAlign. */
function runProps(base, segment) {
  const parts = [
    base.fonts,
    segment.b ? '<w:b/><w:bCs/>' : '',
    segment.u ? '<w:u w:val="single"/>' : '',
    base.sz,
    base.szCs,
    segment.sup ? '<w:vertAlign w:val="superscript"/>' : '',
  ].join('');
  return parts ? `<w:rPr>${parts}</w:rPr>` : '';
}

function rebuildParagraph(paragraph, segments) {
  const open = paragraph.match(/^<w:p\b[^>]*>/);
  if (!open) {
    throw new Error('Could not read paragraph opening tag');
  }
  const pPr = paragraph.match(/<w:pPr>[\s\S]*?<\/w:pPr>/);
  const base = baseRunProps(paragraph);

  const runs = segments
    .map(
      (segment) =>
        `<w:r>${runProps(base, segment)}<w:t xml:space="preserve">${escapeXml(segment.t)}</w:t></w:r>`
    )
    .join('');

  return `${open[0]}${pPr ? pPr[0] : ''}${runs}</w:p>`;
}

function buildTemplate(branch) {
  const parts = collectParts(join(SOURCE_ROOT, branch));
  const documentPart = parts.find((part) => part.path === 'word/document.xml');
  if (!documentPart) {
    throw new Error(`${branch}: word/document.xml missing`);
  }

  const paragraphs = documentPart.text.match(/<w:p\b[^>]*>[\s\S]*?<\/w:p>/g) ?? [];
  let xml = documentPart.text;

  for (const rule of RULES[branch]) {
    const hits = paragraphs.filter((p) => paragraphText(p).includes(rule.match));
    if (hits.length !== 1) {
      throw new Error(
        `${branch}: rule "${rule.match}" matched ${hits.length} paragraphs (expected 1)`
      );
    }
    const replacement = rebuildParagraph(hits[0], rule.segments);
    if (!xml.includes(hits[0])) {
      throw new Error(`${branch}: paragraph for "${rule.match}" not found in document`);
    }
    xml = xml.replace(hits[0], replacement);
  }

  const tokens = [...xml.matchAll(/\{\{([A-Z_]+)\}\}/g)].map((m) => m[1]);
  documentPart.text = xml;

  mkdirSync(OUTPUT_DIR, { recursive: true });
  writeFileSync(
    join(OUTPUT_DIR, `agreement-${branch}.json`),
    JSON.stringify({ branch, parts }),
    'utf8'
  );

  console.log(
    `${branch}: ${parts.length} parts, ${new Set(tokens).size} unique tokens -> ${OUTPUT_DIR}/agreement-${branch}.json`
  );
  console.log(`  tokens: ${[...new Set(tokens)].sort().join(', ')}`);
}

for (const branch of Object.keys(RULES)) {
  buildTemplate(branch);
}
