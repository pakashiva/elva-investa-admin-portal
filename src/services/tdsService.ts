import { supabase } from '../lib/supabase';
import type {
  TdsDashboardData,
  TdsFilingRow,
  TdsQuarterSlice,
  TdsReferralFilingRow,
} from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function mapRow(row: Record<string, unknown>): TdsFilingRow {
  return {
    investment_id: String(row.investment_id ?? ''),
    customer_name: String(row.customer_name ?? ''),
    investment_code: String(row.investment_code ?? '—'),
    principal: asNumber(row.principal),
    gross_interest: asNumber(row.gross_interest),
    tds_percent: asNumber(row.tds_percent),
    tds_amount: asNumber(row.tds_amount),
    quarter: asNumber(row.quarter),
    period: String(row.period ?? ''),
  };
}

function mapReferralRow(row: Record<string, unknown>): TdsReferralFilingRow {
  return {
    id: String(row.id ?? ''),
    referrer_name: String(row.referrer_name ?? '—'),
    referred_name: String(row.referred_name ?? '—'),
    investment_id: String(row.investment_id ?? ''),
    investment_code: String(row.investment_code ?? '—'),
    referral_code: String(row.referral_code ?? '—'),
    capital_amount: asNumber(row.capital_amount),
    gross_bonus: asNumber(row.gross_bonus),
    tds_rate: asNumber(row.tds_rate),
    tds_amount: asNumber(row.tds_amount),
    net_bonus: asNumber(row.net_bonus),
    status: String(row.status ?? ''),
    credited_on: String(row.credited_on ?? ''),
    quarter: asNumber(row.quarter),
    period: String(row.period ?? ''),
  };
}

function mapQuarter(row: Record<string, unknown>): TdsQuarterSlice {
  return {
    quarter: asNumber(row.quarter),
    label: String(row.label ?? ''),
    amount: asNumber(row.amount),
    isCurrent: Boolean(row.isCurrent),
  };
}

export async function getTdsDashboard(): Promise<TdsDashboardData> {
  const { data, error } = await supabase.rpc('admin_get_tds_dashboard');

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  const kpis = (payload.kpis ?? {}) as Record<string, unknown>;

  return {
    kpis: {
      totalTds: asNumber(kpis.totalTds),
      totalInterestTds: asNumber(kpis.totalInterestTds),
      totalReferralTds: asNumber(kpis.totalReferralTds),
      currentMonthTds: asNumber(kpis.currentMonthTds),
      monthInterestTds: asNumber(kpis.monthInterestTds),
      monthReferralTds: asNumber(kpis.monthReferralTds),
      currentFyTds: asNumber(kpis.currentFyTds),
      fyInterestTds: asNumber(kpis.fyInterestTds),
      fyReferralTds: asNumber(kpis.fyReferralTds),
      fyLabel: String(kpis.fyLabel ?? ''),
      fyShort: String(kpis.fyShort ?? ''),
    },
    rows: Array.isArray(payload.rows)
      ? payload.rows.map((row) => mapRow(row as Record<string, unknown>))
      : [],
    referralRows: Array.isArray(payload.referral_rows)
      ? payload.referral_rows.map((row) => mapReferralRow(row as Record<string, unknown>))
      : [],
    quarters: Array.isArray(payload.quarters)
      ? payload.quarters.map((row) => mapQuarter(row as Record<string, unknown>))
      : [],
  };
}
