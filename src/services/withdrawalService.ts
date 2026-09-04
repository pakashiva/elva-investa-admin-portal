import { supabase } from '../lib/supabase';
import type {
  WithdrawalDecision,
  WithdrawalFilter,
  WithdrawalListResult,
  WithdrawalListRow,
  WithdrawalStatus,
} from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asStatus(value: unknown): WithdrawalStatus {
  const status = String(value ?? 'Processing');
  if (
    status === 'On Hold' ||
    status === 'Approved' ||
    status === 'Paid' ||
    status === 'Rejected'
  ) {
    return status;
  }
  return 'Processing';
}

function mapRow(row: Record<string, unknown>): WithdrawalListRow {
  return {
    id: String(row.id ?? ''),
    status: asStatus(row.status),
    strategy: row.strategy === 'partial' ? 'partial' : 'full',
    customer_name: String(row.customer_name ?? ''),
    investment_code: String(row.investment_code ?? '—'),
    plan_name: String(row.plan_name ?? 'Active plan'),
    available_principal: asNumber(row.available_principal),
    withdrawal_amount: asNumber(row.withdrawal_amount),
    tds_amount: asNumber(row.tds_amount),
    tds_percent: asNumber(row.tds_percent),
    net_payout: asNumber(row.net_payout),
    bank_name: row.bank_name ? String(row.bank_name) : null,
    account_number: row.account_number ? String(row.account_number) : null,
    requested_on: String(row.requested_on ?? ''),
    updated_at: String(row.updated_at ?? ''),
    agreement_ok: Boolean(row.agreement_ok),
  };
}

export async function listWithdrawals(params: {
  filter: WithdrawalFilter;
  search: string;
  page: number;
  pageSize: number;
}): Promise<WithdrawalListResult> {
  const { data, error } = await supabase.rpc('admin_list_withdrawals', {
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
      ? payload.rows.map((row) => mapRow(row as Record<string, unknown>))
      : [],
    total: asNumber(payload.total),
    limit: asNumber(payload.limit) || params.pageSize,
    offset: asNumber(payload.offset),
  };
}

export async function decideWithdrawal(id: string, action: WithdrawalDecision) {
  const { data, error } = await supabase.rpc('admin_decide_withdrawal', {
    p_id: id,
    p_action: action,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id ?? id),
    status: asStatus(row.status),
    net_payout: asNumber(row.net_payout),
    withdrawal_amount: asNumber(row.withdrawal_amount),
    action,
  };
}
