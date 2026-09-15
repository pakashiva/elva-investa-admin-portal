import { supabase } from '../lib/supabase';
import type {
  AgreementRenewalDetail,
  AgreementRenewalMode,
  InvestmentDecision,
  InvestmentQueueKind,
  InvestmentRequestDetail,
  InvestmentRequestFilter,
  InvestmentRequestListResult,
  InvestmentRequestListRow,
  InvestmentRequestStatus,
  RenewalDecision,
} from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asStatus(value: unknown): InvestmentRequestStatus {
  const status = String(value ?? 'Pending');
  if (
    status === 'Under Review' ||
    status === 'Active' ||
    status === 'Closed' ||
    status === 'Approved' ||
    status === 'Rejected'
  ) {
    return status;
  }
  return 'Pending';
}

function asKind(value: unknown): InvestmentQueueKind {
  return value === 'renewal' ? 'renewal' : 'investment';
}

function asMode(value: unknown): AgreementRenewalMode | null {
  if (value === 'same_amount' || value === 'increase') {
    return value;
  }
  return null;
}

function mapListRow(row: Record<string, unknown>): InvestmentRequestListRow {
  return {
    id: String(row.id ?? ''),
    kind: asKind(row.kind),
    code: row.code ? String(row.code) : null,
    request_id: row.request_id ? String(row.request_id) : null,
    customer_name: String(row.customer_name ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    plan_name: String(row.plan_name ?? 'New Fund Request'),
    fund_amount: asNumber(row.fund_amount),
    status: asStatus(row.status),
    created_at: String(row.created_at ?? ''),
    mode: asMode(row.mode),
    increment_amount:
      row.increment_amount === null || row.increment_amount === undefined
        ? null
        : asNumber(row.increment_amount),
    agreement_id: row.agreement_id ? String(row.agreement_id) : null,
  };
}

export async function listInvestmentRequests(params: {
  filter: InvestmentRequestFilter;
  search: string;
  page: number;
  pageSize: number;
}): Promise<InvestmentRequestListResult> {
  const { data, error } = await supabase.rpc('admin_list_investment_requests', {
    p_filter: params.filter,
    p_search: params.search.trim() || null,
    p_limit: params.pageSize,
    p_offset: (params.page - 1) * params.pageSize,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  return {
    rows: Array.isArray(payload.rows)
      ? payload.rows.map((row) => mapListRow(row as Record<string, unknown>))
      : [],
    total: asNumber(payload.total),
    limit: asNumber(payload.limit) || params.pageSize,
    offset: asNumber(payload.offset),
  };
}

export async function getInvestmentRequest(
  id: string
): Promise<InvestmentRequestDetail> {
  const { data, error } = await supabase.rpc('admin_get_investment_request', {
    p_id: id,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  const bank = row.bank as Record<string, unknown> | null;

  return {
    id: String(row.id ?? ''),
    code: row.code ? String(row.code) : null,
    request_id: row.request_id ? String(row.request_id) : null,
    status: asStatus(row.status),
    plan_name: String(row.plan_name ?? 'New Fund Request'),
    fund_amount: asNumber(row.fund_amount),
    interest_rate: asNumber(row.interest_rate),
    tds_percent: asNumber(row.tds_percent),
    payout_day: asPayoutDay(row.payout_day),
    created_at: String(row.created_at ?? ''),
    user_id: String(row.user_id ?? ''),
    customer_name: String(row.customer_name ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    referral_code: row.referral_code ? String(row.referral_code) : null,
    referrer_user_id: row.referrer_user_id ? String(row.referrer_user_id) : null,
    referrer_name: row.referrer_name ? String(row.referrer_name) : null,
    referral_rate: asNumber(row.referral_rate) || 0.01,
    referral_tds_rate: asNumber(row.referral_tds_rate) || 0.02,
    active_portfolio: asNumber(row.active_portfolio),
    active_plans: asNumber(row.active_plans),
    bank: bank
      ? {
          bank_name: String(bank.bank_name ?? ''),
          account_number: String(bank.account_number ?? ''),
          ifsc_code: String(bank.ifsc_code ?? ''),
        }
      : null,
  };
}

export async function getAgreementRenewal(id: string): Promise<AgreementRenewalDetail> {
  const { data, error } = await supabase.rpc('admin_get_agreement_renewal', {
    p_id: id,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  const bank = row.bank as Record<string, unknown> | null;
  const mode = asMode(row.mode) ?? 'same_amount';
  const statusRaw = String(row.status ?? 'Pending');
  const status =
    statusRaw === 'Approved' || statusRaw === 'Rejected' ? statusRaw : 'Pending';

  return {
    id: String(row.id ?? ''),
    kind: 'renewal',
    status,
    mode,
    agreement_id: String(row.agreement_id ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    customer_name: String(row.customer_name ?? ''),
    current_amount: asNumber(row.current_amount),
    increment_amount:
      row.increment_amount === null || row.increment_amount === undefined
        ? null
        : asNumber(row.increment_amount),
    new_principal: asNumber(row.new_principal),
    created_at: String(row.created_at ?? ''),
    user_id: String(row.user_id ?? ''),
    investment_id: String(row.investment_id ?? ''),
    plan_no: row.plan_no ? String(row.plan_no) : null,
    plan_name: String(row.plan_name ?? 'Investment'),
    investment_status: String(row.investment_status ?? ''),
    fund_amount: asNumber(row.fund_amount),
    interest_rate: asNumber(row.interest_rate),
    tds_percent: asNumber(row.tds_percent),
    payout_day: asPayoutDay(row.payout_day),
    invested_date: row.invested_date ? String(row.invested_date) : null,
    bank: bank
      ? {
          bank_name: String(bank.bank_name ?? ''),
          account_number: String(bank.account_number ?? ''),
          ifsc_code: String(bank.ifsc_code ?? ''),
        }
      : null,
  };
}

const PAYOUT_DAY_OPTIONS = [1, 5, 10, 15, 20, 25] as const;

function asPayoutDay(value: unknown): number {
  const parsed = Number(value);
  if (PAYOUT_DAY_OPTIONS.includes(parsed as (typeof PAYOUT_DAY_OPTIONS)[number])) {
    return parsed;
  }
  return 10;
}

export async function updateInvestmentTerms(
  id: string,
  interestRate: number,
  tdsPercent: number,
  payoutDay: number,
  referralRate: number = 0.01
): Promise<void> {
  const { error } = await supabase.rpc('admin_update_investment_terms', {
    p_id: id,
    p_interest_rate: interestRate,
    p_tds_percent: tdsPercent,
    p_payout_day: payoutDay,
    p_referral_rate: referralRate,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }
}

export async function decideInvestment(id: string, action: InvestmentDecision) {
  const { data, error } = await supabase.rpc('admin_decide_investment', {
    p_id: id,
    p_action: action,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id ?? id),
    request_id: row.request_id ? String(row.request_id) : null,
    status: asStatus(row.status),
    fund_amount: asNumber(row.fund_amount),
    action,
  };
}

export async function decideAgreementRenewal(id: string, action: RenewalDecision) {
  const { data, error } = await supabase.rpc('admin_decide_agreement_renewal', {
    p_id: id,
    p_action: action,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id ?? id),
    agreement_id: row.agreement_id ? String(row.agreement_id) : null,
    status: String(row.status ?? ''),
    fund_amount: asNumber(row.fund_amount),
    action,
  };
}

export type CustomerOption = {
  user_id: string;
  customer_id: string | null;
  full_name: string;
  mobile_number: string;
  investment_count: number;
};

export type CustomerBankOption = {
  id: string;
  account_number: string;
  branch_name: string;
  bank_name: string;
  ifsc_code: string;
  account_type: string;
  is_primary: boolean;
};

export async function listCustomerOptions(search = ''): Promise<CustomerOption[]> {
  const { data, error } = await supabase.rpc('admin_list_customer_options', {
    p_search: search.trim() || null,
    p_limit: 50,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  if (!Array.isArray(data)) {
    return [];
  }

  return data.map((item) => {
    const row = item as Record<string, unknown>;
    return {
      user_id: String(row.user_id ?? ''),
      customer_id: row.customer_id ? String(row.customer_id) : null,
      full_name: String(row.full_name ?? ''),
      mobile_number: String(row.mobile_number ?? ''),
      investment_count: Number(row.investment_count ?? 0) || 0,
    };
  });
}

export async function listCustomerBanks(userId: string): Promise<CustomerBankOption[]> {
  const { data, error } = await supabase.rpc('admin_list_customer_banks', {
    p_user_id: userId,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  if (!Array.isArray(data)) {
    return [];
  }

  return data.map((item) => {
    const row = item as Record<string, unknown>;
    return {
      id: String(row.id ?? ''),
      account_number: String(row.account_number ?? ''),
      branch_name: String(row.branch_name ?? ''),
      bank_name: String(row.bank_name ?? ''),
      ifsc_code: String(row.ifsc_code ?? ''),
      account_type: String(row.account_type ?? ''),
      is_primary: Boolean(row.is_primary),
    };
  });
}

export type CreateInvestmentInput = {
  userId: string;
  amount: number;
  bankAccountId: string;
  fundTitle: string;
};

export async function createInvestmentRequest(input: CreateInvestmentInput) {
  const { data, error } = await supabase.rpc('admin_create_investment_request', {
    p_user_id: input.userId,
    p_amount: input.amount,
    p_bank_account_id: input.bankAccountId,
    p_fund_title: input.fundTitle.trim(),
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  return {
    ok: Boolean(row.ok),
    id: String(row.id ?? ''),
    user_id: String(row.user_id ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    fund_amount: asNumber(row.fund_amount),
    status: asStatus(row.status),
  };
}
