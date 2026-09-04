import { supabase } from '../lib/supabase';
import type { PortalSettings } from '../types/admin';
import { parseRpcError } from '../utils/format';

function asNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function mapSettings(row: Record<string, unknown>): PortalSettings {
  return {
    platform_name: String(row.platform_name ?? ''),
    support_email: String(row.support_email ?? ''),
    support_phone: String(row.support_phone ?? ''),
    default_currency: String(row.default_currency ?? 'INR'),
    min_investment_amount: asNumber(row.min_investment_amount),
    max_investment_amount: asNumber(row.max_investment_amount),
    gateway_provider: String(row.gateway_provider ?? ''),
    merchant_id: String(row.merchant_id ?? ''),
    api_key: String(row.api_key ?? ''),
    api_secret: String(row.api_secret ?? ''),
    max_single_transaction: asNumber(row.max_single_transaction),
    daily_transfer_limit: asNumber(row.daily_transfer_limit),
    updated_at: row.updated_at ? String(row.updated_at) : null,
  };
}

export async function getPortalSettings(): Promise<PortalSettings> {
  const { data, error } = await supabase.rpc('admin_get_portal_settings');
  if (error) {
    throw new Error(parseRpcError(error));
  }
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function savePortalSettings(
  settings: Omit<PortalSettings, 'updated_at'>
): Promise<PortalSettings> {
  const { data, error } = await supabase.rpc('admin_save_portal_settings', {
    p_platform_name: settings.platform_name,
    p_support_email: settings.support_email,
    p_support_phone: settings.support_phone,
    p_default_currency: settings.default_currency,
    p_min_investment_amount: settings.min_investment_amount,
    p_max_investment_amount: settings.max_investment_amount,
    p_gateway_provider: settings.gateway_provider,
    p_merchant_id: settings.merchant_id,
    p_api_key: settings.api_key,
    p_api_secret: settings.api_secret,
    p_max_single_transaction: settings.max_single_transaction,
    p_daily_transfer_limit: settings.daily_transfer_limit,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function resetPortalSettings(): Promise<PortalSettings> {
  const { data, error } = await supabase.rpc('admin_reset_portal_settings');
  if (error) {
    throw new Error(parseRpcError(error));
  }
  return mapSettings((data ?? {}) as Record<string, unknown>);
}
