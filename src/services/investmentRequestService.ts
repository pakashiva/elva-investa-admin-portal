import { supabase } from '../lib/supabase';
import type {
  InvestmentDecision,
  InvestmentRequestDetail,
  InvestmentRequestFilter,
  InvestmentRequestListResult,
  InvestmentRequestListRow,
  InvestmentRequestStatus,
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
    status === 'Rejected'
  ) {
    return status;
  }
  return 'Pending';
}

function mapListRow(row: Record<string, unknown>): InvestmentRequestListRow {
  return {
    id: String(row.id ?? ''),
    request_id: row.request_id ? String(row.request_id) : null,
    customer_name: String(row.customer_name ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    plan_name: String(row.plan_name ?? 'New Fund Request'),
    fund_amount: asNumber(row.fund_amount),
    status: asStatus(row.status),
    created_at: String(row.created_at ?? ''),
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
    request_id: row.request_id ? String(row.request_id) : null,
    status: asStatus(row.status),
    plan_name: String(row.plan_name ?? 'New Fund Request'),
    fund_amount: asNumber(row.fund_amount),
    interest_rate: asNumber(row.interest_rate),
    tds_percent: asNumber(row.tds_percent),
    created_at: String(row.created_at ?? ''),
    user_id: String(row.user_id ?? ''),
    customer_name: String(row.customer_name ?? ''),
    customer_id: row.customer_id ? String(row.customer_id) : null,
    kyc_verified: Boolean(row.kyc_verified),
    active_portfolio: asNumber(row.active_portfolio),
    active_plans: asNumber(row.active_plans),
    bank: bank
      ? {
          bank_name: String(bank.bank_name ?? ''),
          account_number: String(bank.account_number ?? ''),
          ifsc_code: String(bank.ifsc_code ?? ''),
          verified: Boolean(bank.verified),
        }
      : null,
  };
}

export async function updateInvestmentTerms(
  id: string,
  interestRate: number,
  tdsPercent: number
): Promise<void> {
  const { error } = await supabase.rpc('admin_update_investment_terms', {
    p_id: id,
    p_interest_rate: interestRate,
    p_tds_percent: tdsPercent,
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
