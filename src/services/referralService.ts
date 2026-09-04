import { supabase } from '../lib/supabase';
import type { ReferralListRow, ReferralPayoutStatus, ReferralsPageData } from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asStatus(value: unknown): ReferralPayoutStatus {
  return String(value) === 'Paid' ? 'Paid' : 'Pending';
}

function mapRow(row: Record<string, unknown>): ReferralListRow {
  return {
    id: String(row.id ?? ''),
    status: asStatus(row.status),
    referrer_user_id: String(row.referrer_user_id ?? ''),
    referred_user_id: String(row.referred_user_id ?? ''),
    referrer_name: String(row.referrer_name ?? 'Referrer'),
    referred_name: String(row.referred_name ?? 'Referred customer'),
    investment_id: String(row.investment_id ?? ''),
    investment_code: row.investment_code ? String(row.investment_code) : null,
    referral_code: String(row.referral_code ?? ''),
    capital_amount: asNumber(row.capital_amount),
    referral_rate: asNumber(row.referral_rate),
    gross_bonus: asNumber(row.gross_bonus),
    tds_rate: asNumber(row.tds_rate),
    tds_amount: asNumber(row.tds_amount),
    net_bonus: asNumber(row.net_bonus),
    lifetime_paid_net: asNumber(row.lifetime_paid_net),
    created_at: String(row.created_at ?? ''),
  };
}

export async function listReferrals(params: {
  page: number;
  pageSize: number;
}): Promise<ReferralsPageData> {
  const { data, error } = await supabase.rpc('admin_list_referrals', {
    p_limit: params.pageSize,
    p_offset: (params.page - 1) * params.pageSize,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  const settings = (payload.settings ?? {}) as Record<string, unknown>;
  const kpis = (payload.kpis ?? {}) as Record<string, unknown>;

  return {
    settings: {
      referral_rate: asNumber(settings.referral_rate) || 0.01,
      tds_rate: asNumber(settings.tds_rate) || 0.02,
    },
    kpis: {
      totalReferrals: asNumber(kpis.totalReferrals),
      grossCommission: asNumber(kpis.grossCommission),
      tdsAmount: asNumber(kpis.tdsAmount),
      netCommission: asNumber(kpis.netCommission),
    },
    rows: Array.isArray(payload.rows)
      ? payload.rows.map((row) => mapRow(row as Record<string, unknown>))
      : [],
    total: asNumber(payload.total),
    limit: asNumber(payload.limit) || params.pageSize,
    offset: asNumber(payload.offset),
  };
}

export async function decideReferral(id: string, action: 'pay' | 'hold') {
  const { data, error } = await supabase.rpc('admin_decide_referral', {
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
    net_bonus: asNumber(row.net_bonus),
    action,
  };
}
