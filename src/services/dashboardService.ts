import { supabase } from '../lib/supabase';
import type { ChartRangeMonths, DashboardData } from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function getDashboard(months: ChartRangeMonths): Promise<DashboardData> {
  const { data, error } = await supabase.rpc('admin_get_dashboard', {
    p_months: months,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  const kpis = (payload.kpis ?? {}) as Record<string, unknown>;

  return {
    kpis: {
      totalWealthManaged: asNumber(kpis.totalWealthManaged),
      totalInvested: asNumber(kpis.totalInvested),
      activeInvestments: asNumber(kpis.activeInvestments),
      activeInvestmentsThisWeek: asNumber(kpis.activeInvestmentsThisWeek),
      interestPaidYtd: asNumber(kpis.interestPaidYtd),
      tdsDeductedYtd: asNumber(kpis.tdsDeductedYtd),
      totalWithdrawals: asNumber(kpis.totalWithdrawals),
      totalCustomers: asNumber(kpis.totalCustomers ?? kpis.verifiedCustomers),
      newRegistrationsThisWeek: asNumber(kpis.newRegistrationsThisWeek),
      pendingRequests: asNumber(kpis.pendingRequests),
      pendingInvestments: asNumber(kpis.pendingInvestments),
      pendingWithdrawals: asNumber(kpis.pendingWithdrawals),
    },
    wealthSeries: Array.isArray(payload.wealthSeries)
      ? payload.wealthSeries.map((point) => {
          const row = point as Record<string, unknown>;
          return {
            month: String(row.month ?? ''),
            label: String(row.label ?? ''),
            wealth: asNumber(row.wealth),
          };
        })
      : [],
    flowSeries: Array.isArray(payload.flowSeries)
      ? payload.flowSeries.map((point) => {
          const row = point as Record<string, unknown>;
          return {
            month: String(row.month ?? ''),
            label: String(row.label ?? ''),
            inflow: asNumber(row.inflow),
            outflow: asNumber(row.outflow),
          };
        })
      : [],
  };
}
