import { supabase } from '../lib/supabase';
import type { TdsDashboardData, TdsFilingRow, TdsQuarterSlice } from '../types/admin';
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
      currentMonthTds: asNumber(kpis.currentMonthTds),
      currentFyTds: asNumber(kpis.currentFyTds),
      fyLabel: String(kpis.fyLabel ?? ''),
      fyShort: String(kpis.fyShort ?? ''),
    },
    rows: Array.isArray(payload.rows)
      ? payload.rows.map((row) => mapRow(row as Record<string, unknown>))
      : [],
    quarters: Array.isArray(payload.quarters)
      ? payload.quarters.map((row) => mapQuarter(row as Record<string, unknown>))
      : [],
  };
}
