import { supabase } from '../lib/supabase';
import type { AgreementBranch, AgreementPayload, ChequeFieldPresets } from '../types/admin';
import { amountToIndianWords } from '../utils/amountWords';
import { buildDocx, downloadBlob, escapeDocxText, type DocxPart } from '../utils/docx';
import { parseRpcError } from '../utils/format';

const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const templateCache = new Map<AgreementBranch, DocxPart[]>();

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asText(value: unknown): string {
  return value === null || value === undefined ? '' : String(value);
}

function mapPayload(raw: Record<string, unknown>): AgreementPayload {
  const agreement = (raw.agreement ?? {}) as Record<string, unknown>;
  const investment = (raw.investment ?? {}) as Record<string, unknown>;
  const customer = (raw.customer ?? {}) as Record<string, unknown>;
  const bank = raw.bank as Record<string, unknown> | null;
  const nominee = raw.nominee as Record<string, unknown> | null;

  return {
    agreement: {
      id: asText(agreement.id),
      branch: agreement.branch === 'raichur' ? 'raichur' : 'ballari',
      agreement_date: asText(agreement.agreement_date),
      period_from: asText(agreement.period_from),
      period_to: asText(agreement.period_to),
      cheque_no: asText(agreement.cheque_no),
      cheque_bank_name: asText(agreement.cheque_bank_name),
      cheque_bank_address: asText(agreement.cheque_bank_address),
      renewal_id: agreement.renewal_id ? asText(agreement.renewal_id) : null,
    },
    investment: {
      id: asText(investment.id),
      code: investment.code ? asText(investment.code) : null,
      plan_name: asText(investment.plan_name),
      fund_amount: asNumber(investment.fund_amount),
      interest_rate: asNumber(investment.interest_rate),
      tds_percent: asNumber(investment.tds_percent),
    },
    customer: {
      customer_id: customer.customer_id ? asText(customer.customer_id) : null,
      full_name: asText(customer.full_name),
      address: asText(customer.address),
      email: asText(customer.email),
      mobile: asText(customer.mobile),
      pan: asText(customer.pan),
      aadhaar: asText(customer.aadhaar),
    },
    bank: bank
      ? {
          holder: asText(bank.holder),
          account_number: asText(bank.account_number),
          ifsc_code: asText(bank.ifsc_code),
          bank_name: asText(bank.bank_name),
          branch_name: asText(bank.branch_name),
        }
      : null,
    nominee: nominee
      ? {
          name: asText(nominee.name),
          relation: asText(nominee.relation),
          aadhaar: asText(nominee.aadhaar),
          pan: asText(nominee.pan),
          mobile: asText(nominee.mobile),
        }
      : null,
  };
}

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => asText(item).trim())
    .filter((item) => item.length > 0);
}

export async function listChequePresets(): Promise<ChequeFieldPresets> {
  const { data, error } = await supabase.rpc('admin_list_cheque_presets');

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  return {
    cheque_nos: asStringList(row.cheque_nos),
    bank_names: asStringList(row.bank_names),
    bank_addresses: asStringList(row.bank_addresses),
  };
}

export async function saveInvestmentAgreement(input: {
  investmentId: string;
  branch: AgreementBranch;
  chequeNo: string;
  chequeBankName: string;
  chequeBankAddress: string;
  renewalId?: string | null;
}): Promise<AgreementPayload> {
  const { data, error } = await supabase.rpc('admin_save_investment_agreement', {
    p_investment_id: input.investmentId,
    p_branch: input.branch,
    p_cheque_no: input.chequeNo.trim(),
    p_cheque_bank_name: input.chequeBankName.trim(),
    p_cheque_bank_address: input.chequeBankAddress.trim(),
    p_renewal_id: input.renewalId ?? null,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  return mapPayload((data ?? {}) as Record<string, unknown>);
}

export async function getInvestmentAgreement(
  investmentId: string,
  renewalId: string | null = null
): Promise<AgreementPayload | null> {
  const { data, error } = await supabase.rpc('admin_get_investment_agreement', {
    p_investment_id: investmentId,
    p_renewal_id: renewalId,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  if (!data) {
    return null;
  }

  return mapPayload(data as Record<string, unknown>);
}

// ---------------------------------------------------------------------------
// Template merge
// ---------------------------------------------------------------------------

async function loadTemplate(branch: AgreementBranch): Promise<DocxPart[]> {
  const cached = templateCache.get(branch);
  if (cached) {
    return cached;
  }

  const response = await fetch(`/templates/agreement-${branch}.json`, {
    cache: 'force-cache',
  });
  if (!response.ok) {
    throw new Error(
      `Agreement template could not be loaded (${response.status}). Redeploy the app so /templates/agreement-${branch}.json is available.`
    );
  }

  const payload = (await response.json()) as { parts?: DocxPart[] };
  if (!Array.isArray(payload.parts) || payload.parts.length === 0) {
    throw new Error('Agreement template file is empty or invalid.');
  }

  templateCache.set(branch, payload.parts);
  return payload.parts;
}

function parseDate(value: string): Date {
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  return new Date(year, (month || 1) - 1, day || 1);
}

function ordinalSuffix(day: number): string {
  if (day % 100 >= 11 && day % 100 <= 13) return 'th';
  if (day % 10 === 1) return 'st';
  if (day % 10 === 2) return 'nd';
  if (day % 10 === 3) return 'rd';
  return 'th';
}

function dottedDate(value: string): string {
  const date = parseDate(value);
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${day}.${month}.${date.getFullYear()}`;
}

function dashedDate(value: string): string {
  return dottedDate(value).replace(/\./g, '-');
}

/** 0.05 -> "5%", 0.1 -> "10%", 0 -> "0%" */
function ratePercent(rate: number): string {
  const percent = Math.round(rate * 1000000) / 10000;
  return `${percent}%`;
}

function groupAadhaar(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (digits.length !== 12) {
    return value.trim();
  }
  return `${digits.slice(0, 4)} ${digits.slice(4, 8)} ${digits.slice(8)}`;
}

function localMobile(value: string): string {
  const digits = value.replace(/\D/g, '');
  return digits.length > 10 ? digits.slice(-10) : digits;
}

function buildTokens(payload: AgreementPayload): Record<string, string> {
  const date = parseDate(payload.agreement.agreement_date);
  const day = date.getDate();
  const amount = Math.round(payload.investment.fund_amount);

  return {
    DATE_DAY: String(day).padStart(2, '0'),
    DATE_DAY_SUFFIX: ordinalSuffix(day),
    DATE_MONTH: MONTHS[date.getMonth()],
    DATE_YEAR: String(date.getFullYear()),
    DATE_DMY: dashedDate(payload.agreement.agreement_date),
    CUSTOMER_NAME: payload.customer.full_name,
    CUSTOMER_ADDRESS: payload.customer.address.trim().replace(/[.,\s]+$/, ''),
    CUSTOMER_AADHAAR: groupAadhaar(payload.customer.aadhaar),
    CUSTOMER_PAN: payload.customer.pan,
    CUSTOMER_EMAIL: payload.customer.email,
    CUSTOMER_PHONE: localMobile(payload.customer.mobile),
    AMOUNT: amount.toLocaleString('en-IN'),
    AMOUNT_WORDS: amountToIndianWords(amount),
    INTEREST_RATE: ratePercent(payload.investment.interest_rate),
    TDS_RATE: ratePercent(payload.investment.tds_percent),
    PERIOD_FROM: dottedDate(payload.agreement.period_from),
    PERIOD_TO: dottedDate(payload.agreement.period_to),
    CHEQUE_NO: payload.agreement.cheque_no,
    CHEQUE_BANK_NAME: payload.agreement.cheque_bank_name,
    CHEQUE_BANK_ADDRESS: payload.agreement.cheque_bank_address.replace(/[.,\s]+$/, ''),
    BANK_HOLDER: payload.bank?.holder || payload.customer.full_name,
    BANK_ACCOUNT: payload.bank?.account_number ?? '',
    BANK_IFSC: payload.bank?.ifsc_code ?? '',
    BANK_NAME: payload.bank?.bank_name ?? '',
    BANK_BRANCH: payload.bank?.branch_name ?? '',
    NOMINEE_NAME: payload.nominee?.name ?? '',
    NOMINEE_AADHAAR: groupAadhaar(payload.nominee?.aadhaar ?? ''),
    NOMINEE_PAN: payload.nominee?.pan ?? '',
    NOMINEE_RELATION: payload.nominee?.relation ?? '',
    NOMINEE_PHONE: localMobile(payload.nominee?.mobile ?? ''),
  };
}

export function agreementFileName(payload: AgreementPayload): string {
  const name = payload.customer.full_name.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const plan = payload.investment.code ?? 'INV';
  const suffix = payload.agreement.renewal_id ? 'Renewal' : 'Agreement';
  return `Loan-${suffix}-${plan}-${name || 'Customer'}.docx`;
}

export async function downloadAgreementDocx(payload: AgreementPayload): Promise<void> {
  const parts = await loadTemplate(payload.agreement.branch);
  const tokens = buildTokens(payload);

  const filled = parts.map((part) => {
    if (part.path !== 'word/document.xml') {
      return part;
    }
    const text = part.text.replace(/\{\{([A-Z_]+)\}\}/g, (match, token: string) =>
      token in tokens ? escapeDocxText(tokens[token]) : match
    );
    return { path: part.path, text };
  });

  downloadBlob(buildDocx(filled), agreementFileName(payload));
}
