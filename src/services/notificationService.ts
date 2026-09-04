import { supabase } from '../lib/supabase';
import type { AdminNotification, NotificationFilter, NotificationKind } from '../types/admin';
import { parseRpcError } from '../utils/format';

function asKind(value: unknown): NotificationKind {
  if (value === 'withdrawal' || value === 'customer') {
    return value;
  }
  return 'investment';
}

function mapRow(row: Record<string, unknown>): AdminNotification {
  const amount = row.amount == null ? null : Number(row.amount);
  return {
    key: String(row.key ?? ''),
    kind: asKind(row.kind),
    customer_name: String(row.customer_name ?? 'Customer'),
    amount: Number.isFinite(amount) ? amount : null,
    plan_name: row.plan_name ? String(row.plan_name) : null,
    occurred_at: String(row.occurred_at ?? ''),
    href: String(row.href ?? '/'),
    unread: Boolean(row.unread),
  };
}

export async function listNotifications(params: {
  filter: NotificationFilter;
  kind: 'all' | NotificationKind;
  search: string;
  from: string | null;
  to: string | null;
}): Promise<{ rows: AdminNotification[]; unreadCount: number }> {
  const { data, error } = await supabase.rpc('admin_list_notifications', {
    p_filter: params.filter,
    p_kind: params.kind,
    p_search: params.search.trim() || null,
    p_from: params.from,
    p_to: params.to,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  return {
    rows: Array.isArray(payload.rows)
      ? payload.rows.map((row) => mapRow(row as Record<string, unknown>))
      : [],
    unreadCount: Number(payload.unreadCount ?? 0) || 0,
  };
}

export async function setNotificationRead(key: string, read: boolean): Promise<void> {
  const { error } = await supabase.rpc('admin_set_notification_read', {
    p_key: key,
    p_read: read,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }
}

export async function markAllNotificationsRead(): Promise<void> {
  const { error } = await supabase.rpc('admin_mark_all_notifications_read');
  if (error) {
    throw new Error(parseRpcError(error));
  }
}

export async function getUnreadNotificationCount(): Promise<number> {
  const { data, error } = await supabase.rpc('admin_unread_notification_count');
  if (error) {
    throw new Error(parseRpcError(error));
  }
  const payload = (data ?? {}) as Record<string, unknown>;
  return Number(payload.unreadCount ?? 0) || 0;
}

export function notifyNotificationsChanged() {
  window.dispatchEvent(new Event('admin-notifications-changed'));
}
